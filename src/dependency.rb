require_relative 'logger'
require_relative 'project'

# Dependency is an interface to represent the dependency that targets and rules have
class Dependency

  # validate the value to which this dependency was resolved
  # @param value the value
  # @return true if the value matches this dependency, false otherwise
  def validate (context, value)
    true
  end

  def get_product
    nil
  end

  # determine the product is older than any of the needs
  # @param product a dependency
  # @param needs an array of needs
  # @return true if the product is older than some need
  def self.is_older_than(product, needs)
    _p = product
    if _p.is_a? OptionalDependency then
      _p = _p.dependency
    end

    _result=true

    # since an array may be passed in, it's best to just
    # wrap the dependency as a Dependency before flattening it
    needs = Dependency.create(needs)
    needs = needs.flatten

    # now, we have a flat array of needs which we can just check
    needs.each do |n|
      _n = n
      if _n.is_a? OptionalDependency then
        _n = _n.dependency
      end

      _result = _n.is_newer_than(_p)
      if _result.nil? then
        # interpret a nil as an out-of-date condition
        $logger.debug("Cannot determine if #{_p} older than #{_n}")
        _result = true
      end
      if _result then
        $logger.debug("#{_p} is older than #{_n}")
        break
      end
      $logger.debug("#{_p} is newer than #{_n}")
    end
    if _result then
      $logger.debug("Product needs to be rebuilt: #{product}")
    end
    _result
  end

  def flatten
    self
  end

  # determine if this dependency is newer than the specified dependency
  # return true if this dependency is more recent than the given dependency, false otherwise, and nil if unknown
  def is_newer_than(dependency)
    nil
  end

  # resolve all dependencies in the context
  def self.resolveDependencies (context, dependencies)
    _result = {}
    dependencies.each_with_index { |dependency, key| _result[key] = context.resolve dependency }
    return _result
  end

  def self.create (param)

    $logger.info("Create dependency class #{param.class.name} : #{param}");
    if param.is_a? Array then
      return Dependencies.new (param.uniq.collect { |v| Dependency.create v })
    end

    if param.is_a? Dependency then
      return param
    end

    if param.instance_of? String then
      return FileDependency.new param
    end

    if param.instance_of? Symbol then
      return TargetDependency.new param
    end

    raise "Failed to create a dependency for #{param} of type #{param.class}"
  end

end

class GenericDependency < Dependency

  attr_reader :value

  def initialize (hashable)
    @value = hashable
  end

  def ==(other)
    self.class === other &&
        other.value == @value
  end

  alias eql? ==

  def hash
    @value.hash # XOR
  end

end

class RuleDependency < GenericDependency

  attr_reader :rule

  def initialize(name)
    super(name)
  end

  alias_method :name, :value

  def to_s
    "RuleDep(#{name})"
  end
end

class OptionalDependency < GenericDependency

  def initialize (dep)
    if dep.is_a? OptionalDependency then
      dep = dep.dependency
    end
    super(Dependency.create(dep))
  end

  alias_method :dependency, :value

  def get_product
    dependency.get_product
  end

  def flatten
    dependency
  end

  def to_s
    "+#{dependency}"
  end
end

class Dependencies < GenericDependency

  def initialize args
    super args.clone
  end

  alias_method :dependencies, :value

  def flatten
    _result = []
    dependencies.each do |x| 
      v = x.flatten
      if v.is_a? Array then 
        _result.concat(v)
      else
        _result.push(v)
      end
    end
    _result
  end

  def to_s
    "MDep:#{dependencies.to_s}"
  end

end


class FileDependency < GenericDependency


  def initialize (file)
    super(file)
  end

  alias_method :file, :value

  def directory
    return File.dirname file
  end

  def validate (context, value)
    $logger.warn("FIXME: HARDCODED CONDITION")
    (value == file) && (true || (exists context))
  end

  def exists (context)
    return File.file? file
  end

  def older_than (date)
    _time = File.mtime file
    _time < date
  end

  def to_s
    file.to_s
  end

  def is_newer_than(other)
    if other.is_a? FileDependency then
      if (File.exists?(file) && File.exists?(other.file)) then
        return (File.mtime(file) > File.mtime(other.file))
      end
    end
    nil
  end

  def get_product
    file
  end
end

class TargetDependency < GenericDependency


  def initialize (target)
    super(target.to_s)
  end

  alias_method :target, :value

  def to_s
    "TDep:#{target}"
  end
end

class MakeDependency < GenericDependency

  def initialize (dep)
    super(Dependency.create(dep))
  end

  alias_method :dependency, :value

  def to_s
    "MDep:#{dependency}"
  end
end

