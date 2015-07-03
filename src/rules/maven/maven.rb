require_relative '../../logger'
require 'net/http'
require 'rexml/document'
require 'fileutils'

module Maven

  # the default repository
  MAVEN_CENTRAL_URI = 'https://repository.sonatype.org/service/local/artifact/maven/redirect'

  # the maximum number of redirects that will be allowed when accessing the repository
  MAXIMUM_NUMBER_OF_REDIRECTS = 1

  # the root directory for the repository
  LOCAL_REPOSITORY_ROOT = "#{Dir.home}/.m2/mason"

  def self.get_artifact (artifact, uri, max_redirects)

    _dest = artifact.path

    if (artifact.version != 'LATEST') && (File.exists? _dest) then
      # nothing to do if the file already exists
      $logger.info "Artifact already fetched #{artifact} : #{_dest}"
      return artifact;
    end


    if max_redirects < 0 then
      raise 'Too many redirects'
    end

    _http = Net::HTTP.new(uri.host, uri.port)
    _http.use_ssl = uri.scheme == 'https'

    _request = Net::HTTP::Get.new(uri.request_uri)

    _file = nil
    _response = _http.request(_request) do |response|
      if  response.is_a? Net::HTTPOK then
        if _file.nil? then
          FileUtils.mkdir_p(File.dirname(_dest))
          _file = File.new _dest, 'w'
        end
        response.read_body _file
      end
      response
    end

    if !_file.nil? then
      _file.close
    end

    if _response.is_a? Net::HTTPOK then
      artifact
    elsif _response.is_a?(Net::HTTPRedirection) then
      $logger.info("Redirect to #{_response['location']}")
      uri = URI(_response['location'])
      # because of the way things may be represented in the URI, we can only rely on the version, packaging
      _parsedArtifact = parse_artifact_from_uri(uri)
      artifact = Artifact.new(artifact.group, artifact.artifact, _parsedArtifact.version, _parsedArtifact.packaging, artifact.repository)
      get_artifact(artifact, uri, max_redirects-1)
    else
      raise "Failed to fetch artifact #{artifact} : #{_response.message}"
    end
  end

  def self.parse_artifact_from_uri (uri)
    _path = uri.path

    _packaging = File.extname _path
    if _packaging.empty? then
      _packaging = nil
    else
      _packaging = _packaging[1..-1];
    end

    _path = File.dirname _path

    _version = File.basename _path
    _path = File.dirname _path

    _artifact = File.basename _path
    _path = File.dirname _path

    _group = File.basename _path
    _path = File.dirname _path
    _path = File.dirname _path

    _repository = File.basename _path

    Artifact.new(_group, _artifact, _version, _packaging, _repository)
  end


  # a maven artifact descriptor
  class Artifact

    attr_reader :group, :artifact, :version, :repository, :packaging

    def initialize (group, artifact, version=nil, packaging=nil, repository=nil)

      if group.nil? then
        raise 'Null group'
      end

      if   artifact.nil? then
        raise 'Null artifact'
      end

      if repository.nil? then
        repository='central-proxy'
      end
      if version.nil? then
        version = 'LATEST'
      end
      if packaging.nil? then
        packaging = 'jar'
      end

      @group, @artifact, @version, @repository, @packaging = group, artifact, version, repository, packaging
    end

    def ==(other)
      self.class === other &&
          other.group == @group &&
          other.artifact == @artifact &&
          other.repository == @repository &&
          other.version == @version &&
          other.packaging == @packaging
    end

    alias eql? ==

    def hash
      @group.hash ^ @artifact.hash ^ @repository.hash ^ @version.hash
    end

    def to_s
      "Artifact(group=#{@group}, artifact=#{@artifact}, version=#{@version}, packaging=#{@packaging},repository=#{@repository})"
    end

    # get the path at which this artifact is stored or would be stored when fetched
    def path
      _group = @group.gsub('.', '/')
      "#{LOCAL_REPOSITORY_ROOT}/#{_group}/#{@artifact}/#{@version}/#{@artifact}-#{@version}.#{@packaging}"
    end

    # get the pom artifact corresponding to this artifact
    # @return the artifact object that corresponds the pon
    def pom
      _result = self
      if @packaging != 'pom' then
        _result = Artifact.new @group, @artifact, @version, 'pom', @repository
      end
      _result
    end


    # fetch this artifact from the specified repository
    def fetch (repository_url = nil)

      if repository_url.nil? then
        repository_url= MAVEN_CENTRAL_URI
      end

      _params = {
          :r => @repository,
          :g => @group,
          :a => @artifact,
          :v => @version
      }
      _params[:p] = @packaging unless @packaging.nil?

      _uri = URI(repository_url)
      _uri.query= URI.encode_www_form(_params)


      _actualArtifact = Maven.get_artifact self, _uri, MAXIMUM_NUMBER_OF_REDIRECTS

      _actualArtifact
    end

  end

  class Dependency
    attr_reader :group, :artifact, :version, :type, :scope, :optional

    def initialize (group, artifact, version, scope=nil, type=nil, optional=false)
      @group, @artifact, @version, @scope, @optional = group, artifact, version, scope, optional

      if scope.nil? then
        scope = 'compile'
      end
      @type =type
      if type.nil? then
        type = 'jar'
      end
      @type =type
    end

    def ==(other)
      self.class === other &&
          other.group == @group &&
          other.artifact == @artifact &&
          other.scope == @scope &&
          other.version == @version &&
          other.optional == @optional &&
          other.type == @type
    end

    alias eql? ==

    def hash
      @group.hash ^ @artifact.hash ^ @type.hash ^ @version.hash ^ @scope.hash
    end

    def to_s
      "Dependency(group=#{@group}, artifact=#{@artifact}, version=#{@version}, type=#{@type}, scope=#{@scope},optional=#{@optional})"
    end

    def to_pom_artifact
      Artifact.new(@group, @artifact, @version, 'pom')
    end

    def fetch(repository_url = nil)
      _pom = pom repository_url
      return _pom.artifact.fetch(repository_url)
    end

    def pom(repository_url = nil)
      _artifact = to_pom_artifact
      _pom = POM.new(_artifact, repository_url)
      _pom;
    end

  end

  # The pom file for some artifact
  class POM

    attr_reader :artifact, :parent;

    def initialize (artifact, repository_url=nil)
      @repository = artifact.repository;
      _artifact = artifact.pom.fetch(repository_url)
      _file = File.open(_artifact.path)
      @xml = REXML::Document.new(_file.read)
      _file.close
      @properties = POM.get_properties @xml

      _version = POM.get_text(@xml, 'project/parent/version')
      _group =POM.get_text(@xml, 'project/parent/groupId')
      _artifact =POM.get_text(@xml, 'project/parent/artifactId')
      if _version.nil? || _group.nil? || _artifact.nil? then
        @parent = nil
      else
        @parent = POM.new(Artifact.new(_group, _artifact, _version, 'pom'), repository_url)
      end

      _version =POM.get_text(@xml, 'project/version', _version)
      _group =POM.get_text(@xml, 'project/groupId', _group)
      _artifact =POM.get_text(@xml, 'project/artifactId')
      _packaging =POM.get_text(@xml, 'project/packaging', 'jar')

      if (_version != artifact.version) || (_group != artifact.group) || (_artifact!=artifact.artifact) then
        $logger.info "Warning: POM descriptor for #{artifact} does not match the POM url"
        _version = artifact.version
        _group = artifact.group
        _artifact = artifact.artifact
      end


      @artifact = Artifact.new(_group, _artifact, _version, _packaging, artifact.repository)
    end

    def in_scope(current_scope, dependency_scope)
      current_scope == dependency_scope
    end

    def replace_variables (text)
      if text.nil? then
        nil
      else
        @properties.each { |k, v| text.gsub!(k, v) }
        text.gsub!('${project.groupId}', @artifact.group)
        text.gsub!('${project.artifactId}', @artifact.artifact)
        text.gsub!('${project.version}', @artifact.version)
        text
      end
    end

    def dependencies (scope = 'compile')
      _dependencies = []
      @xml.elements.each('project/dependencies/dependency') do |e|
        _scope = POM.get_element_text(e, 'scope', 'compile')
        if in_scope(scope, _scope) then

          _group = POM.get_element_text(e, 'groupId')
          _artifact = POM.get_element_text(e, 'artifactId')
          _version = POM.get_element_text(e, 'version')
          _type = POM.get_element_text(e, 'type')
          _optional = POM.get_element_text(e, 'optional', 'false')

          _group = replace_variables _group
          _artifact = replace_variables _artifact
          _version = replace_variables _version
          _type = replace_variables _type
          _optional = replace_variables _optional

          _dependencies << Dependency.new(_group, _artifact, _version, _scope, _type, _optional=='true')
        end
      end
      _dependencies
    end

    def self.get_properties (doc)
      _props = {}
      doc.elements.each('project/properties/*') do
      |e|
        _props["${#{e.name}}"] = text_of(e)
      end
      _props
    end

    def self.get_text(doc, path, defaultValue=nil)
      _text = nil
      doc.elements.each(path) do |e|
        if _text.nil? then
          _text = (e.texts).join()
        else
          $logger.info "Warning: multiple child elements found #{child}"
        end
      end
      if _text.nil?
        _text = defaultValue
      end
      _text
    end

    def self.get_element_text(element, child, defaultValue = nil)
      _text = nil
      element.each_element(child) do |e|
        if _text.nil? then
          _text = text_of(e)
        else
          $logger.info "Warning: multiple child elements found #{child}"
        end
      end
      if _text.nil?
        _text = defaultValue
      end
      _text
    end

    def self.text_of (e)
      return (e.texts).join()
    end
  end

end
