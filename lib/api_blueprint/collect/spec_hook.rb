module ApiBlueprint::Collect::SpecHook
  @@controller_name = nil
  @@action_name = nil

  class << self
    def controller_name=(name)
      @@controller_name = name
    end

    def action_name=(name)
      @@action_name = name
    end

    def controller_name
      @@controller_name
    end

    def action_name
      @@action_name
    end
  end

  def self.included(base)

    base.before(:each) do |example|
      @base_example = example

      if ENV['API_BLUEPRINT_DUMP'] == '1'
        data = {
          'title_parts' => example_description_parts(example)
        }
        File.write(ApiBlueprint::Collect::Storage.spec_dump, data.to_yaml)
      end
    end

    base.after(:each) do |example|
      dump_blueprint(example) if ENV['API_BLUEPRINT_DUMP'] == '1'
    end

    def set_param_description(param_name, description)
      @base_example.metadata[:param_definitions] ||= {}
      if param_name.is_a? Array
        tmp = @base_example.metadata[:param_definitions]
        param_name.each do |param|
          tmp[param.to_s] ||= {}
          tmp = tmp[param.to_s]
        end
        tmp.merge!({ description: description })
      else
        @base_example.metadata[:param_definitions][param_name.to_s] = (@base_example.metadata[:param_definitions][param_name.to_s] || {}).merge({ description: description })
      end
    end

    def set_param_definition(param_name, type, example_value, description)
      @base_example.metadata[:param_definitions] ||= {}
      if param_name.is_a? Array
        tmp = @base_example.metadata[:param_definitions]
        param_name.each do |param|
          tmp[param.to_s] ||= {}
          tmp = tmp[param.to_s]
        end
        tmp.merge!({ type: type, example: example_value, description: description })
      else
        @base_example.metadata[:param_definitions][param_name.to_s] = (@base_example.metadata[:param_definitions][param_name.to_s] || {}).merge({ type: type, example: example_value, description: description })
      end
    end

    unless base.method_defined?(:set_description)
      def set_description(description)
        @base_example.metadata[:ex_description] = "\n\n#{description}\n"
      end
    end
  end

  class Parser
    attr_reader :input, :headers

    def initialize(input)
      @input = input
    end

    def method
      input.method.to_s.upcase
    end

    def params
      # Reject action and controller params as they are internal params used by
      # Rails. Additionally reject all params that are inside url path and not
      # in query string
      input.params.reject do |k,_|
        ['action', 'controller'].include?(k) ||
          params_in_request_path.include?(k)
      end
    end

    def headers
      @headers ||=  Hash[input.headers.env.select do |k, v|
        (k.start_with?("HTTP_X_") ||  k.start_with?("HTTP_") || k == 'ACCEPT') && v
      end.map do |k, v|
        [human_header_key(k), v]
      end]
    end

    def body
      if input.content_type == 'application/json'
        if input.body != 'null'
          JSON.parse(input.body)
        else
          ""
        end
      else
        input.body
      end
    end

    private

    def human_header_key(key)
      key.sub("HTTP_", '').split("_").map do |x|
        x.downcase
      end.join("_")
    end

    def params_in_request_path
      required_parts = []

      # Find ActionDispatch::Journey::Route object matching current route
      Rails.application.routes.router.recognize(@input) do |route, _matches, _parameters|
        # required_names method will return param names that are inside request
        # path, most likely id params required for REST-like routes
        required_parts = route.path.required_names
      end

      required_parts
    end
  end

  def dump_blueprint_around
    yield
  ensure
    dump_blueprint
  end

  def dump_blueprint(example)
    file       = ApiBlueprint::Collect::Storage.request_dump
    in_parser  = Parser.new(request)
    out_parser = Parser.new(response)

    api_blueprint_keys = %w(x_api_blueprint_description)
    api_blueprint_headers = in_parser.headers.slice(*api_blueprint_keys)
    api_blueprint_keys.each{|k| in_parser.headers.delete(k) }

    data = {
      'metadata' => {
        'description' => example.metadata[:ex_description] || request.headers['HTTP_X_API_BLUEPRINT_DESCRIPTION'],
        'param_definitions'  => example.metadata[:param_definitions]
      },
      'request' => {
        'path'         => request.path,
        'method'       => in_parser.method,
        'params'       => in_parser.params,
        'headers'      => in_parser.headers,
        'content_type' => request.content_type,
        'accept'       => request.accept
      },
      'response' => {
        'status'       => response.status,
        'content_type' => response.content_type,
        'body'         => out_parser.body,
        'headers'      => response.headers.to_h
      },
      'route' => {
        'controller'   => @@controller_name,
        'action'       => @@action_name
      }
    }

    spec = ApiBlueprint::Collect::Storage.spec_dump
    if File.exists?(spec)
      data['spec'] = YAML::load_file(spec)
    end

    File.write(file, data.to_yaml)
  end
  private

  def example_description_parts(example)
    parts = []
    parts << example.metadata[:description_args].join(' ')
    at = example.metadata[:example_group]

    while at && at[:description_args]
      parts << at[:description_args].join(' ')
      at = at[:parent_example_group]
    end

    parts.reverse!
  end
end
