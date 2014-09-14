require_relative '../../logger'
require_relative '../../dependency'
require_relative '../../spec'
require_relative '../../rule'
require_relative '../../functions'
require 'fileutils'

class Architecture

  attr_reader :os,:node,:release,:machine

  def initialize (os,nodename,release,machine)
    @os = os
    @nodename = nodename
    @release = release
    @machine = machine
  end

  def to_s
    "Architecture(os=#{@os},nodename=#{@nodename},release=#{@release},machine=#{@machine})"
  end

end

class ArchitectureDependency < GenericDependency

  def initialize(name = nil)
    super(name)
  end

  alias_method :name,:value

  def to_s
    "Architecture(#{name})"
  end

end

class ArchitectureSpec < GenericSpec


  def initialize
    super({})
  end

  alias_method :name,:value

  def to_s
    "ArchitectureSpec()"
  end

  def matches (context, dependency)
    dependency.is_a? ArchitectureDependency
  end

end

class DetermineArchitecture < GeneralRule

  def initialize
    super(ArchitectureSpec.new)
  end

  def apply (produces, needs, context)
    _os = shell 'uname -o'
    _nodename = shell 'uname -n'
    _release = shell 'uname -r'
    _machine = shell 'uname -m'

    Architecture.new(_os.join,_nodename.join,_release.join, _machine.join)
  end
end

def architecture
  ArchitectureDependency.new
end
