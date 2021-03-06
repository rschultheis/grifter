require_relative 'grifter/http_service'
require_relative 'grifter/configuration'
require_relative 'grifter/log'
require_relative 'grifter/blankslate'
require_relative 'grifter/instrumentation'

class Grifter
  include Grifter::Configuration
  include Grifter::Instrumentation

  def default_options
    {
      grift_globs: ['*_grifts/**/*_grifts.rb'],
      authenticate: false,
      load_from_config_file: true,
      services: {},
      instrumentation: false,
    }
  end

  def initialize options={}
    options = default_options.merge(options)
    @config = if options[:load_from_config_file]
                options.merge load_config_file(options)
              else
                options
              end

    #setup the services
    @services = []
    @config[:services].each_pair do |service_name, service_config|
      service = HTTPService.new(service_config)
      define_singleton_method service_name.intern do
        service
      end
      @services << service
    end

    #setup the grifter methods if any
    if @config[:grift_globs]
      @config[:grift_globs].each do |glob|
        Dir[glob].each do |grifter_file|
          load_grifter_file grifter_file
        end
      end
    end

    if @config[:authenticate]
      self.grifter_authenticate_do
    end

    start_instrumentation if @config[:instrumentation]
  end

  attr_reader :services

  #this allows configuration to be accessed in grift scripts
  def grifter_configuration
    @config.clone
  end

  def load_grifter_file filename
    Log.debug "Loading extension file '#{filename}'"
    #by evaling in a anonymous module, we protect this class's namespace
    anon_mod = Module.new
    with_local_load_path File.dirname(filename) do
      anon_mod.class_eval(IO.read(filename), filename, 1)
    end
    self.extend anon_mod
  end

  def run_script_file filename
    Log.info "Running data script '#{filename}'"
    raise "No such file '#{filename}'" unless File.exist? filename
    #by running in a anonymous class, we protect this class's namespace
    anon_class = BlankSlate.new(self)
    with_local_load_path File.dirname(filename) do
      anon_class.instance_eval(IO.read(filename), filename, 1)
    end
  end

  #calls all methods that end with grifter_authenticate
  def grifter_authenticate_do
    auth_methods = self.singleton_methods.select { |m| m =~ /grifter_authenticate$/ }
    auth_methods.each do |m|
      Log.debug "Executing a grifter_authentication on method: #{m}"
      self.send(m)
    end
  end

  private
  def with_local_load_path load_path, &block
    $: << load_path
    rtn = yield block
    #delete only the first occurrence, in case something else if changing load path too
    idx = $:.index(load_path)
    $:.delete_at(idx) if idx
    rtn
  end
end
