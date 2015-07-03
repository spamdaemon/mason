require_relative 'logger'
require_relative 'dependency'
require_relative 'project'

# Spec is an interface to represent the Spec that targets and rules have
class Spec

  # determine if a dependency matches this spec
  def matches (context, dependency)
    false
  end

  def find_variables (context, dependency)
    []
  end


  # turn a dependency spec into an actual dependency
  def to_dependency (context, product, variables)
    raise 'to_dependency: No implemented';
  end

  def self.create (param)

    if param.is_a? Dependency then
      return DependencySpec.new(param)
    end

    if param.is_a? Proc then
      return FunctionalSpec.new(param)
    end

    if param.is_a? Spec then
      return param
    end

    if param.instance_of? String then
      return FileSpec.new(param)
    end

    if param.instance_of? Regexp then
      return FileSpec.new(param)
    end

    if param.instance_of? Symbol then
      return TargetSpec.new(param)
    end

    raise "Failed to create a spec for #{param}"
  end

end




class GenericSpec < Spec

  attr_reader :value;

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

class RuleSpec < GenericSpec

  def initialize(name)
    super(name)
  end

  alias_method :name, :value

  def matches (context, dependency)
    if (dependency.is_a? RuleDependency) && (dependency.name==name) then
      return true
    end
    false
  end

  def find_variables (context, dependency)
    []
  end

end

class FunctionalSpec < Spec

  attr_reader :block;

  def initialize (block)
    if block.nil? then
      raise "No block given"
    end

    @block = block
  end

  def ==(other)
    self.class === other &&
        other.block === @block
  end

  alias eql? ==

  def hash
    @block.hash # XOR
  end

  def matches (context, dependency)
    $logger.info 'FunctionalSpec cannot appear on left-hand side of a rule'
    false
  end

  def find_variables (context, dependency)
    return []
  end

  def to_dependency (context, product, variables)
    @block.call product, variables, context;
  end
end

class FileSpec < GenericSpec

  def initialize (file)

    if file.nil? ||(file.is_a? Regexp) then
      super(file)
    elsif file.index(/([^%]|^)%/).nil? then
      super(file)
    else
      # turn the file into a regular expression by replacing
      # each % with "(.+)"
      _regexp = file.gsub('.', "\\.")
      # use named captures instead : (<name>regex) will yield a match  { name => ... }
      _regexp = _regexp.gsub(/([^%]|^)%/,"\\1(.+)")
      _regexp = "^#{_regexp}$"
      _compiled = Regexp.compile(_regexp)
      $logger.info("Compiled regexp for file #{file} is #{_compiled}")
      super(_compiled)
    end
  end

  alias_method :file, :value

  # turn a dependency spec into an actual dependency
  def to_dependency (context, product, variables)
    _result = file.clone
    variables.each_with_index { |v, i| _result.gsub! "{#{i}}", v.to_s }
    $logger.debug "Variables #{variables.to_s}"
    $logger.debug "Result #{_result}"
    $logger.debug "Spec #{file}"
    Dependency.create _result
  end

  def find_variables (context, dependency)
    if file.nil? then
      return [dependency.file];
    end

    if file.is_a? Regexp then
      match = file.match dependency.file
      match.captures.unshift dependency.file;
    else
      return [dependency.file];
    end
  end

  def matches (context, dependency)
    if dependency.is_a? FileDependency then
      if file.nil? then
        return true
      end

      if file.is_a? Regexp then
        return file.match(dependency.file)
      else
        return file == dependency.file
      end
    end
    false
  end

  def to_s
    "FSpec:#{file}"
  end

end



class TargetSpec < GenericSpec

  def initialize (target)
    super(target.to_s)
  end

  # turn a dependency spec into an actual dependency
  def to_dependency (context, product, variables)
    _result = target.clone;
    variables.each_with_index { |v, i| _result.gsub! '\{'+i.to_s+'\}', v.to_s }
    TargetDependency.new _result
  end

  def find_variables (context, dependency)
    return [dependency.target];
  end

  def matches (context, dependency)
    if dependency.is_a? TargetDependency then
      return target.nil? || (target == dependency.target)
    else
      return false
    end
  end

  alias_method :target, :value

  def to_s
    "TSpec:#{target}"
  end
end


class DependencySpec < GenericSpec

  def initialize (dependency)
    super(dependency)
  end

  # turn a dependency spec into an actual dependency
  def to_dependency (context, product, variables)
    dependency
  end

  def find_variables (context, dependency)
    return [dependency.target];
  end

  def matches (context, x)
    x === dependency
  end

  alias_method :dependency, :value

  def to_s
    "DepSpec:#{dependency}"
  end
end

class WrapperSpec < GenericSpec 

  def initialize (clazz, dep)
    super(Spec.create(dep))
    @class = clazz;
  end

  alias_method :dependency, :value

  def create_dependency(dep)
    @class.new(dep)
  end

  def compatible? (dep)
    dep.is_a? @class
  end

  # turn a dependency spec into an actual dependency
  def to_dependency (context, product, variables)
    _dependency = dependency.to_dependency(context,product,variables)
    create_dependency(_dependency)
  end

  def find_variables (context, dep)
    dependency.find_variables(context,dep)
  end

  def matches (context, dep)
    compatible?(dep) && (dependency.matches(context,dep.dependency))
  end
end

class MakeDependencySpec < WrapperSpec

  def initialize (dep)
    super(MakeDependency,dep)
  end
end

class OptionalDependencySpec < GenericSpec

  def initialize (dep)
    super(OptionalDependency,dep)
  end
end

def dependency_of(d)
  MakeDependencySpec.new(d)
end

def optional(d)
  OptionalSpec.new(d)
end

