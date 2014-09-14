require_relative '../../logger'
require_relative '../../dependency'
require_relative '../../spec'
require_relative '../../rule'
require_relative '../../functions'
require_relative 'maven'

require 'net/http'


class MavenArtifact < GenericDependency

  def initialize (artifact)
    super(artifact)
    @artifact = artifact
  end

  alias_method :artifact, :value

  def to_s
    "MavenArtifact(#{@artifact.to_s})"
  end
end

class MavenDependency < GenericDependency

  attr_reader :dependency

  def initialize (group, artifact, version='LATEST', scope='compile', type='jar')
    super(Maven::Dependency.new(group, artifact, version, scope, type))
  end

  alias_method :dependency, :value

  def to_s
    "MavenDep(#{dependency.to_s})"
  end
end

class MavenDependencySpec < Spec

  def initialize
  end

  def matches (context, dependency)
    if !(dependency.is_a? MavenDependency) then
      return false
    end
    true
  end

  def find_variables (context, dependency)
    []
  end


  # turn a dependency spec into an actual dependency
  def to_dependency (context, product, variables)
    raise 'MavenDependencySpec cannot be used as a dependency of a rule'
  end

end

class MavenArtifactSpec < Spec

  def initialize
  end

  def matches (context, dependency)
    if !(dependency.is_a? MavenArtifact) then
      return false
    end
    true
  end

  def find_variables (context, dependency)
    []
  end


  # turn a dependency spec into an actual dependency
  def to_dependency (context, product, variables)
    raise 'MavenArtifactSpec cannot be used as a dependency of a rule'
  end

end

class MavenFetch < Rule


  def initialize
    @spec = MavenArtifactSpec.new
  end

  def dependencies
    []
  end

  # get the product spec for this rule
  # @return the spec for the product that this rule generates
  def spec
    @spec
  end

  def apply (produces, needs, context)

    if !produces.is_a? MavenArtifact then
      raise "Not a MavenArtifact #{produces}"
    end

    # fetch the artifact for the dependency now
    echo "Fetching #{produces.artifact}"
    _artifact = produces.artifact.fetch

    # return the path to the fetched artifact
    _artifact.path
  end

  @@instance = MavenFetch.new

  def self.instance
    @@instance
  end

  private_class_method :new

end

class MavenResolve < Rule


  def initialize
    @spec = MavenDependencySpec.new
  end

  def dependencies
    []
  end

  # get the product spec for this rule
  # @return the spec for the product that this rule generates
  def spec
    @spec
  end

  def apply (produces, needs, context)

    if !produces.is_a? MavenDependency then
      raise "Not a MavenDependency #{produces}"
    end

    if produces.dependency.type == 'pom' then
      return  MavenArtifact.new(produces.dependency.to_pom_artifact)
    end

    # fetch the artifact for the dependency now
    _pom = produces.dependency.pom

    _result = []
    _result << MavenArtifact.new(_pom.artifact)


      # generate the dependencies of the artifact itself; for now, ignore scope
      _pom.dependencies.each do |d|
        if !d.optional then
          _result << MavenDependency.new(d.group, d.artifact, d.version, d.scope, d.type)
        end
      end

    Dependencies.create (_result.uniq())
  end

  @@instance = MavenResolve.new

  def self.instance
    @@instance
  end

  private_class_method :new

end

def artifact(group, artifact, version=nil, scope=nil, type=nil)
  MavenDependency.new(group, artifact, version, scope, type)
end
