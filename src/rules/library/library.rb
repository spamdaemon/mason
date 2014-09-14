require_relative '../../logger'
require_relative '../../dependency'
require_relative '../../spec'
require_relative '../../rule'
require 'fileutils'

class Library



  def path
    nil
  end

end

class LibraryDependency < GenericDependency

  def initialize name
    super(name)
  end

  alias_method :name,:value

  def to_s
    "Library(#{name})"
  end

end

class LibrarySpec < GenericSpec
  def initialize name
    super(name)
  end

  alias_method :name,:value

  def to_s
    "LibrarySpec(#{name})"
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

class FindLibrary < GeneralRule


end

def lib(name)
  LibraryDependency.new name
end