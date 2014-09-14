require_relative 'logger'
require_relative 'spec'
require_relative 'dependency'
require_relative 'project'

# a rule is generic sequence of steps that will be
# executed
class Rule

  def gates
    []
  end

  def dependencies
    []
  end

  # get the product spec for this rule
  # @return the spec for the product that this rule generates
  def spec
    nil
  end

  def apply (context, produces, needs)
    raise 'Unimplemented rule'
  end
end

class GeneralRule < Rule

  def initialize (produces, dependencies=nil, build=nil)
    if produces.nil? then
      raise 'No product specified for rule'
    end

    @produces = produces

    if dependencies.nil? then
      @dependencies = []
    else
      @dependencies = dependencies.clone
    end
    if build.nil? then
      $logger.info("No build procedure specified for #{produces}");
      @build = nil
    else
      @build = build
    end
  end

  def dependencies
    @dependencies
  end

  def spec
    @produces
  end

  def apply (produces, needs, context)
    # invoke the build function to create the dependency
    if @build.nil? then
      needs
    else
      @build.call produces, needs, context
    end
  end
end


class MakeOptionalDependency < Rule


  def initialize
    @produces = OptionalDependencySpec.new
  end

  def dependencies
    []
  end

  def spec
    @produces
  end

  def apply (produces, needs, context)
    _result = nil
    begin
      _result= context.make(produces.dependency)
    rescue
      $logger.warn("Dependency #{produces} is optional");
    end
    _result
  end

  @@instance = MakeOptionalDependency.new

  def self.instance
    @@instance
  end

  private_class_method :new
end


class CheckFileExists < GeneralRule

  def initialize
    super (FileSpec.new nil), nil, Proc.new { |produces, needs, context|
      if File.exists? produces.file then
        produces.file
      else
        raise "File does not exist #{produces.file}"
      end
    }
  end

  @@instance = CheckFileExists.new

  def self.instance
    @@instance
  end

  private_class_method :new

end


# target rule is a singleton; use TargetRule.instance to access it
class TargetRule < Rule

  def initialize
    @spec = TargetSpec.new nil
  end

  @@instance = TargetRule.new

  def self.instance
    @@instance
  end

  private_class_method :new

  def spec
    @spec
  end

  def apply (produces, needs, context)
    # invoke the build function to create the dependency
    _result context.make_target produces.target
    $logger.info "MAKE TARGET #{produces} => #{_result}"
  end

end

# target rule is a singleton; use TargetRule.instance to access it
class MakeDependencies < Rule

  class DependenciesSpec < Spec
    def initialize
    end

    @@instance = DependenciesSpec.new

    def self.instance
      @@instance
    end

    private_class_method :new

    def ==(other)
      self === other
    end

    alias eql? ==

    def hash
      7
    end

    def matches (context, dependency)
      dependency.is_a? Dependencies
    end

    def find_variables (context, dependency)
      []
    end

  end

  def initialize

  end

  @@instance = MakeDependencies.new

  def self.instance
    @@instance
  end

  private_class_method :new

  def spec
    DependenciesSpec.instance
  end

  def apply (produces, needs, context)
    context.make produces.dependencies
  end

end
