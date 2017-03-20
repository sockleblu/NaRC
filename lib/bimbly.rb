# coding: utf-8
$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/../bin")

require 'rest_client'
require 'yaml'
require 'json'
require 'pathname'

class Bimbly
  attr_reader :data_types, :error_codes, :error_names, :obj_sets
  attr_accessor :array, :base_url, :cert, :file, :headers, :password, :pointer, :port, :user

  def initialize(opts = {})
    # Read in setup files
    @error_codes = YAML.load(File.read("#{File.dirname(__FILE__)}/errors_by_code.yml"))
    @error_names = YAML.load(File.read("#{File.dirname(__FILE__)}/errors_by_name.yml"))
    @obj_sets = YAML.load(File.read("#{File.dirname(__FILE__)}/object_sets.yml"))
    @data_types = YAML.load(File.read("#{File.dirname(__FILE__)}/data_types.yml"))
    
    #@doc_pointer = @obj_sets
    new_connection(opts)
    
    gen_methods
  end

  def call_nimble(opts = {})
    verb = opts[:verb]
    payload   = opts[:payload]
    uri = opts[:uri]

    puts verb
    puts uri
    puts payload

    # Check if url is valid
    raise ArgumentError, "Invalid URL: #{uri}" unless uri =~ /\A#{URI::regexp}\z/
    
    begin
      response =  RestClient::Request.execute(
        method: verb.to_sym,
        url: uri,
        ssl_ca_file: @cert,
        headers: @headers,
        payload: payload
      )
    rescue RestClient::ExceptionWithResponse => e
      puts "Response Code: #{e.response.code}"
      puts "Response Headers: #{e.response.headers}"
      puts "Response Body: #{e.response.body}"
      puts "Response Object: #{e.response.request.inspect}"
    end
    
    begin
      JSON.parse(response.body) unless response.nil? || response.body == ''
    rescue JSON::ParserError => e
      puts e
    end
  end

  def new_connection(opts = {})
    @file = opts[:file]
    @file_option = opts[:file_option]
    @array = opts[:array]
    @cert = opts[:cert]
    @port = opts[:port]
    @user = opts[:user]
    @password = opts[:password]
    
    puts file
    puts file_option
    
    return if opts.empty?
    
    if file
      conn_data = YAML.load(File.read(File.expand_path(file)))
      conn_data = conn_data[opts[:file_option]] if opts[:file_option]
      @array = conn_data[:array]
      @cert = conn_data[:cert]
      @user = conn_data[:user]
      @password = conn_data[:password]
    end

    raise ArgumentError, "You must provide an array" if array.nil?
    raise ArgumentError, "You must provide a CA cert" if @cert.nil?
    raise ArgumentError, "You must provide a user" if user.nil?
    raise ArgumentError, "You must provide a password" if password.nil?    

    @base_url = "https://#{array}:#{port}"
    uri = "#{@base_url}/v1/tokens"

    # Get initial connection credentials
    creds = { data: {
                         username: user,
                         password: password
                       }
             }
 
    begin    
      response = RestClient::Request.execute(
        method: :post,
        url: uri,
        payload: creds.to_json,
        ssl_ca_file: @cert,
        ssl_ciphers: 'AESGCM:!aNULL'      
      )
    rescue RestClient::ExceptionWithResponse => e
      puts "Response Code: #{e.response.code}"
      puts "Response Headers: #{e.response.headers}"
      puts "Response Body: #{e.response.body}"
      puts "Response Object: #{e.response.request.inspect}"
    end

    token = JSON.parse(response)["data"]["session_token"]
    @headers = { 'X-Auth-Token' => token }
  end

=begin  

  def valid_json?(json)
    begin
      JSON.parse(json)
      return true
    rescue JSON::ParserError => e
      return false
    end
  end

  # Resets the instance variables to the original settings
  # Maybe resets the pointer variable

  # Displays the info at given pointer location
  def doc
    puts "#{@doc_pointer.to_yaml}"
  end
=end
  
  def object_sets
    @obj_sets.keys.each { |key|
      puts "#{key}"
    }
  end

  def options
    @doc_pointer.keys.each { |key|
      puts "#{key}"
    }
  end
  
  def parameters()
    @params.each { |key, value|
      puts "#{key}: #{value}"
      @data_types[value].each { |data|
        puts "  #{value}: #{data["Desc"]}"
        puts "  Type: "
      }
    }
  end
  
  def available_methods
    self.methods - Object.methods
  end

  alias_method :menu, :available_methods
  
  def data_type(type = nil)
    if type
      @doc_pointer = @data_types[type]
    else
      @doc_pointer = @data_types
    end
    self
  end

#  def data_types
#    @data_types
#  end

  def build_params(hash)
    raise ArgumentError, "Please provide a valid hash for parameters" unless
      hash.instance_of? Hash and hash != {}
    url_params = "?"
    size_count = 0
    hash.each { |key, value|
      url_params = "#{url_params}#{key}=#{value}"
      size_count += 1
      url_params = "#{url_params}&" unless size_count == hash.size
    }
    url_params
  end

  def gen_uri(opts = {})
    url_params = build_params(opts[:params]) if opts[:params]
    uri = "#{@base_url}/#{opts[:url_suffix]}#{url_params}"
  end
  
  def gen_method_hash
    method_hash = {}
    name = ""
    @obj_sets.each { |obj_key, obj_value|
      obj_value.each { |op_key, op_value|
        method_suffix = ""
        op_value.each { |key, value|
          next if not key.match(/DELETE|GET|POST|PUT/)
          if key.match(/id/)
            method_suffix = "_by_id"
          elsif key.match(/detail/)
            method_suffix = "_detailed"
          end
          verb, url_suffix = key.split(' ')
          hash = {}
          hash[:verb] = verb.downcase.to_sym
          hash[:url_suffix] = url_suffix

          name = "#{op_key}_#{obj_key}#{method_suffix}"
          method_hash[name.to_sym] = hash
        }
      }
    }
    method_hash
  end

  def gen_methods
    method_hash = gen_method_hash
    method_hash.each { |method_name, hash|
      define_singleton_method(method_name) { |opts = {}|
        raise ArgumentError, "Please provide id" if method_name.match(/id/) and opts[:id].nil?
        url_suffix = hash[:url_suffix]
        url_suffix = url_suffix.gsub(/\/id/, "/#{opts[:id]}") if method_name.match(/id/)

        uri = gen_uri(url_suffix: url_suffix,
                      params: opts[:params])

        call_nimble(uri: uri,
                    verb: hash[:verb],
                    payload: opts[:payload] )
      }
    }
  end
end