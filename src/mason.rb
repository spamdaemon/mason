#!/usr/bin/ruby
require_relative 'logger'
require_relative 'project'
require_relative 'rules/maven/artifact'
require_relative 'rules/system/architecture'

class MasonProject < Project

  def initialize
    super
    add_default_rule :make_target, TargetRule.instance
    add_default_rule :make_optional, MakeOptionalDependency.instance
    add_default_rule :check_file_exists, CheckFileExists.instance
    add_default_rule :make_dependencies, MakeDependencies.instance
    add_default_rule :as_dependency, MakeDependencyRule.instance

    # maven dependencies are added by default
    add_default_rule :maven_fetch, MavenFetch.instance
    add_default_rule :maven_resolve, MavenResolve.instance
    add_default_rule :determine_architecture, DetermineArchitecture.new

  end

end

_brickfile = 'brickfile.rb'

def next_arg errorMessage
  _arg = ARGV.shift
  if _arg.nil? then
    raise errorMessage
  end
  _arg
end

while ARGV.length > 0 do
  if ARGV[0].start_with? '-' then
    _arg = ARGV.shift
    case _arg
      when '--'
        break
      when '-f'
        _brickfile = next_arg '-f: Missing filename'
      else
        break
    end
  else
    break
  end
end

$logger.level = Logger::WARN

project = MasonProject.new
project.instance_eval(File.read(_brickfile), _brickfile)


begin
  if ARGV.empty? then
    project.make(TargetDependency.new(:Make))
    project.make(TargetDependency.new(:Clean))
  else
    ARGV.each { |target| $logger.info(project.make(TargetDependency.new(target.to_sym))) }
  end
rescue Exception => e
 puts e.message
  puts e.backtrace
end



