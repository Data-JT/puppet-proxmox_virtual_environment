#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

# Error raised on any PVE API failure. Carries structured details that are
# surfaced in the Bolt `_error` object.
class ApiError < StandardError
  attr_reader :details

  def initialize(msg, details: {})
    super(msg)
    @details = details
  end
end

def task_input
  stdin = STDIN.read
  return JSON.parse(stdin) unless stdin.strip.empty?

  ENV.select { |key, _value| key.start_with?('PT_') }
     .transform_keys { |key| key.delete_prefix('PT_') }
end

def bool(value, default: true)
  case value
  when nil then default
  when true, 'true', '1', 1 then true
  when false, 'false', '0', 0 then false
  else
    raise ArgumentError, "Invalid boolean value: #{value.inspect}"
  end
end

def hash_param(input, key)
  value = input[key]
  return {} if value.nil? || value == ''
  return value if value.is_a?(Hash)

  JSON.parse(value)
end

def expand_path(path, path_params)
  path_params.reduce(path) do |expanded, (key, value)|
    expanded.gsub("{#{key}}", URI::DEFAULT_PARSER.escape(value.to_s, %r{[^A-Za-z0-9_.~-]}))
  end
end

def method_class(method)
  {
    'GET'    => Net::HTTP::Get,
    'POST'   => Net::HTTP::Post,
    'PUT'    => Net::HTTP::Put,
    'DELETE' => Net::HTTP::Delete,
  }.fetch(method.to_s.upcase) do
    raise ArgumentError, "Unsupported PVE API method #{method}"
  end
end

def error_details(status, body)
  snippet = body.to_s
  parsed =
    begin
      snippet.empty? ? nil : JSON.parse(snippet)
    rescue JSON::ParserError
      snippet[0, 500]
    end

  { 'status' => status, 'body' => parsed }
end

def handle_response(response)
  status = response.code.to_i
  body = response.body

  unless status.between?(200, 299)
    raise ApiError.new(
      "PVE API returned HTTP #{status}",
      details: error_details(status, body),
    )
  end

  parsed = (body.nil? || body.empty?) ? nil : JSON.parse(body)
  data = (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed

  {
    status: status,
    success: true,
    data: data,
  }
end

def api_request(input)
  host = input.fetch('host')
  port = Integer(input.fetch('port', 8006))
  token_id = input.fetch('token_id')
  token_secret = input.fetch('token_secret')
  method = input.fetch('method').upcase
  path = expand_path(input.fetch('path'), hash_param(input, 'path_params'))
  query = hash_param(input, 'query')
  body = hash_param(input, 'body')

  raise ArgumentError, 'path must start with /' unless path.start_with?('/')

  uri = URI("https://#{host}:#{port}/api2/json#{path}")
  uri.query = URI.encode_www_form(query) unless query.empty?

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 60
  http.verify_mode = bool(input['ssl_verify'], default: true) ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
  ssl_ca_file = input['ssl_ca_file']
  http.ca_file = ssl_ca_file if ssl_ca_file && ssl_ca_file != ''

  request = method_class(method).new(uri)
  request['Authorization'] = "PVEAPIToken=#{token_id}=#{token_secret}"
  request['Content-Type'] = 'application/json'
  request.body = body.to_json unless body.empty?

  handle_response(http.request(request))
end

def run_task(input = nil)
  input ||= task_input
  puts JSON.pretty_generate(api_request(input))
rescue StandardError => error
  details = error.respond_to?(:details) ? error.details : {}
  output = {
    _error: {
      kind: 'proxmox_virtual_environment/api-error',
      msg: error.message,
      details: details,
    },
  }
  puts JSON.pretty_generate(output)
  exit 1
end

run_task if $PROGRAM_NAME == __FILE__
