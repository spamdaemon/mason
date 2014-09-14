require_relative 'logger'
require_relative 'rule'
require_relative 'dependency'
require_relative 'spec'
require_relative 'functions'

class Project

  @@CYCLIC_MARKER = 'CYCLIC_MARKER'
  @@UNRESOLVED_MARKER = 'UNRESOLVED_MARKER'

  public

  def initialize
    @defaultRules = {}
    @rules = {}
    @gatedRules = {}

    # additional dependencies; this is a map of spec -> [spec]
    @additional_dependencies = {}

    # a map of dependents that need to be resolved
    @waiting = {}

    # a map of dependency to value
    @resolved = {}

    # map of things in progress
    @in_progress = {}

    # a list of dependents that are ready
    @ready = []

    @nextRule = 1
    @queue = {}
  end

  def add_rule (name, rule)
    @rules[name] = rule
  end

  def add_default_rule (name, rule)
    @defaultRules[name] = rule
  end

  # make the specified dependency and returns its value
  # @param dependency the dependencies (an array or a dependency) to make
  # @return the value for the dependency
  def make (dependency)
    $logger.info("Make #{dependency}")
    deps = []

    if dependency.is_a? Array then
      deps= dependency.collect { |d| Dependency.create d }
    else
      deps = [(Dependency.create dependency)]
    end

    deps.each { |d| schedule_dependency d }
    deps.each { |d| (execute_until { resolved? d }) }

    _result = deps.collect do |d|
      if resolved? d then
        if @resolved[d].is_a? Dependency then
          make @resolved[d]
        else
          @resolved[d]
        end
      else
        raise "Failed to call make #{d}"
      end
    end


    if dependency.is_a? Array then
      _result
    else
      _result[0]
    end

  end

  # create a rule
  def depends (opts)

    _depends_on = nil
    _produces = nil

      # short notation for rule creation
      opts.each do |k, v|
        if k== :needs then
          _depends_on = v
        elsif k==:produces then
          _produces = v;
        elsif _produces.nil? && _depends_on.nil? then
          _produces, _depends_on = k, v
        end
      end

    if _produces.nil? then
      raise 'No product specified for rule'
    end

    _produces = Spec.create _produces
    _deps = @additional_dependencies[_produces]
    if _deps.nil? then
      _deps = []
      @additional_dependencies[_produces] = _deps
    end

    unless _depends_on.nil? then
      _depends_on = Array(_depends_on)
      _depends_on.map! { |v| Spec.create v }
    end

    _depends_on.each { |v| _deps.push(v) }
  end

  # create a rule
  def rule (opts, &block)

    _depends_on = nil
    _produces = nil
    _name = nil
    _gates = nil

    if opts.is_a? Hash then
      # short notation for rule creation
      opts.each do |k, v|
        if k== :needs then
          _depends_on = v
        elsif k==:name then
          _name = v;
        elsif k==:produces then
          _produces = v;
        elsif k==:gates then
          _gates = v;
        elsif _produces.nil? && _depends_on.nil? then
          _produces, _depends_on = k, v
        end
      end
    else
      _produces = opts
      opts = {}
    end

    if _produces.nil? then
      raise 'No product specified for rule'
    end

    unless _gates.nil? then
      _gates = Array(_gates)
      _gates.map! { |v| Spec.create v }
    end

    unless _depends_on.nil? then
      _depends_on = Array(_depends_on)
      _depends_on.map! { |v| Spec.create v }
    end

      _produces = Spec.create _produces

    if (_name.nil?) && (_produces.is_a? TargetSpec) then
      _name = _produces.target
    elsif _name.nil? then
      _name = @nextRule;
    end
    @nextRule = @nextRule +1

    _rule = GeneralRule.new _produces, _depends_on, block
    if _gates.nil? then
      @rules[_name] = _rule
      $logger.info "Rule : #{_name} : depends on #{_depends_on} and produces #{_produces}"
    else
      $logger.warn('Creating a dynamic rule')
      @gatedRules[_name] = _name
      @rules[_name] = (GeneralRule.new RuleSpec.new(_name), _gates, Proc.new do |product, gates|
        $logger.info("Adding a dynamic rule #{product} : #{gates}")
        @rules[_name] = _rule
        @gatedRules.delete _name
        name
      end)
      _ruleDependency = optional(RuleDependency.new(_name))
      schedule_dependency _ruleDependency
    end
  end

  private

  class Dependent
    attr_accessor :target, :output, :inputs, :unresolvedCount

    def initialize (target, output, inputs)
      @target = target
      @output = output
      @inputs = inputs
      @unresolvedCount = inputs.length
    end

    def resolved?
      @unresolvedCount === 0
    end

  end

  def make_gated_rules

  end

  def match_rule (rules, dependency)
    _name = nil;
    _rule = nil;
    rules.each do |name, rule|
      if (dependency.eql? rule.spec) || (rule.spec.matches self, dependency) then
        if _name.nil? then
          _name = name;
          _rule= rule;
        else
          raise "Ambiguous rules found: #{_name} and #{name} and dependency #{dependency}";
        end
      end
    end
    return _name, _rule;
  end


  # find a rule or a target that can satisfy the specified depdency
  # @param dependency the dependency to be satisfied
  # @return a target or a rule, but never nil
  def match_dependency (dependency)

    # the _target rule
    _target = nil
    _name = nil
    _value = nil

    # if a target wasn't found, then check the configured rules
    _name, _target = match_rule @rules, dependency

    # if a target still hasn't been found, then check the default
    # rules
    if _target.nil? then
      _name, _target = match_rule @defaultRules, dependency
    end

    if _target.nil? then
      raise "Failed to find  target or rule to satisfy the dependency #{dependency}"
    end

    $logger.debug "Found a match for dependency #{dependency} : #{_target}"

    _target
  end

  # convert a list of specs into  dependencies given a spec and dependency that satisfies it
  # @param target a dependency
  # @param targetSpec a target spec that matches the target
  # @param required an array of specs or dependencies that will be resolved with variables defined by the targetSpec
  # @return an array of required dependencies
  def resolve_specs (target, targetSpec, required)
    if required.nil? || required.length === 0 then
      return []
    end

    # find the free variables in the spec
    _freeVariables = targetSpec.find_variables self, target

    # use the free variables to turn a dependency spec into an actual dependency
    _depends = required.collect do |spec|
      if spec.is_a? Spec then
        spec.to_dependency self, target, _freeVariables
      else
        spec
      end
    end

    _depends
  end

  # invoke a target or a rule with all the dependencies it requires and resolved the product to a value
  def invoke (target, produces, required)
    if !(target.is_a? Rule) then
      raise "Unsupported target type #{target.class}"
    end
    _product = nil

    # create a new dependency that we'll use to detect cycles; for now, use product as the
    # key, but it might be better to also consider the required objects; this way, we might
    # actually be able to support recursion!
    _key = produces
    
    $logger.debug "Invoking rule #{target.class} : hash#{_key.hash}:#{_key}"
    ## FIXME: we want to detect cycles, but we also want to support reschedules of dependents
    if false && @in_progress[_key] == true then
      raise "Cyclic dependency detected for hash#{_key.hash}:#{produces}"
    else
      @in_progress[_key] = true
      $logger.debug "BEGIN Apply target hash#{_key.hash}:#{produces}"
      _product = target.apply produces, required, self
      $logger.debug "END Apply target hash#{_key.hash}:#{produces}"
      @in_progress[_key] = false
    end

    if (_product == produces) && (_product.is_a? Dependency) then
      $logger.debug("Rule returned dependency as product; changing to nil to avoid infinite recursion : #{_product}");
      _product = nil;
    end
    _product
  end

  def notify_dependency_resolved (dependency)
    # remove the dependency from the waiting list
    _dependents = @waiting.delete dependency

    if _dependents.nil? then
      return false
    end

    # decrease the number of unresolved dependencies in each dependent
    # and if there none left, put the dependent into the ready list
    _dependents.each do |dependent|
      $logger.debug "Make ready #{dependent.target}"
      dependent.unresolvedCount = dependent.unresolvedCount-1
      if dependent.resolved? then
        @ready.push dependent
      end
    end
    true
  end

  # resolve a dependency with a value
  def resolve_dependency (dependency, value)

    # remember the value
    if !resolved? dependency then
      @resolved[dependency] = value
      $logger.debug "resolve_dependency: newly resolved hash#{dependency.hash}: #{dependency} with #{value}"
      notify_dependency_resolved dependency
    end
  end

  # the dependent may become resolved as part of this function
  def enqueue_dependency (dependency, dependent)
    _dependents = @waiting[dependency]
    if _dependents.nil? then
      _dependents = [];
      @waiting[dependency] = _dependents
    end
    _dependents.push dependent

    if resolved? dependency then
      $logger.debug "enqueue_dependency: already resolved dependency #{dependency}"
      notify_dependency_resolved dependency
    end

    true
  end

  def resolved? (dependency)
    _value = @resolved.assoc(dependency)
    if _value.nil? || _value === @@CYCLIC_MARKER then
      return false
    end
    true
  end

  def resolve_additional_dependencies(dependency)
     _result = []
     @additional_dependencies.each do |spec,deps|
      if spec.matches(self,dependency) then
        $logger.debug("Adding additional dependencies for #{dependency} : #{deps.size}")
        _result.concat(resolve_specs dependency, spec, deps)
      end
    end
    _result
  end

  def schedule_object (dependency, target,dependencies=nil)

    if !@gatedRules.empty? then
      execute_until
    end

    if  @resolved[dependency] === @@CYCLIC_MARKER
      raise "Circular dependency involving #{dependency}"
    end

    if resolved? dependency then
      $logger.debug "schedule_object: already resolved dependency #{dependency}"
      notify_dependency_resolved dependency
      return true
    end

    @resolved[dependency] = @@CYCLIC_MARKER

    if dependencies.nil? then
      dependencies = target.dependencies
      _dependencies = resolve_specs dependency, target.spec, dependencies
      _dependencies.concat(resolve_additional_dependencies(dependency))
    else
      _dependencies = resolve_specs dependency, target.spec, dependencies
    end

    $logger.debug "Dependencies for #{dependency} :  #{_dependencies.to_s}"
    # create a dependent that we'll be able to execute later on when we're ready
    _dependent = Dependent.new target, dependency, _dependencies

    if _dependent.resolved? then
      @ready.push _dependent
    else
      # for each dependency, enqueue it with the dependent
      _dependencies.each do |d|
        enqueue_dependency d, _dependent
      end

      # now, schedule the dependencies themselves
      _dependencies.each do |d|
        schedule_dependency d
      end
    end
    # now, that we've successfully enqueued the entire chain, we can unmark the
    # dependency again
    @resolved.delete dependency

    _dependent
  end

  # schedule the dependency for further execution; this is recursive process
  def schedule_dependency (dependency)
    _target = match_dependency dependency
    if resolved? dependency then
      $logger.debug("Dependency already resolved; schedule dependency #{dependency}")
    else
      schedule_object dependency, _target
    end
    true
  end

  # Execute targets and rules until there are no more, or a block returns false
  # @param blk an optional block
  # @return false if there are no more rules or targets, true if the block returned false

  def execute_until
    while !@ready.empty? do
      _dependent = @ready.pop

      if resolved? _dependent.output then
        $logger.debug("Dependency already resolved; no need to invoke target: #{_dependent.output}")
        next
      end

      _dependencies = Array.new(_dependent.inputs)
      _reschedule = false
      # collect all dependency values
      _inputs = [];
      _dependent.inputs.each_index do |i|
        _dep = _dependencies[i]
        _inputs[i] = @resolved[_dep];
        if _inputs[i].is_a? Dependency then
          _dependencies[i] = _inputs[i]
          # instead of making the dependency, it 
          # would be nicer if we could reschedule the dependent
          #_inputs[i] = make _inputs[i]
          _reschedule = true
        end
      end

      # continue with the loop; not really supported right now
      # don't know why, but we can get cycles if we reschedule
      if _reschedule then
        $logger.debug("Reschedule dependency #{_dependent.output}")
        schedule_object(_dependent.output,_dependent.target,_dependencies)
        next
      end

      _product = nil;
      if !Dependency.is_older_than(_dependent.output, _dependencies) then
        _product = _dependent.output.get_product
      end
      if _product.nil? then
        _product = invoke _dependent.target, _dependent.output, _inputs
      end
      resolve_dependency _dependent.output, _product


      if block_given? then
        _continue = yield _dependent
        if _continue then
          return true;
        end
      end
    end
    false
  end


end

