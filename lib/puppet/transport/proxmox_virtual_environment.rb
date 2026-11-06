# frozen_string_literal: true

require 'net/http'
require 'json'
require 'openssl'
require 'uri'

# @api private
module Puppet::Transport; end

# Internal HTTP client for the Proxmox Virtual Environment REST API,
# configured from the managed pve_transport.yaml file. This is deliberately
# NOT a registered Resource API transport: it has no transport schema and is
# not usable via `puppet device`; providers instantiate it directly from the
# on-disk config.
#
# Recognized connection_info keys:
#   :host          (required) PVE host name or IP address
#   :port          (optional) API port, default 8006
#   :token_id      (required) API token ID, e.g. user@realm!token
#   :token_secret  (required) API token secret (String or Sensitive)
#   :ssl_verify    (optional) verify the TLS certificate, default true
#   :ssl_ca_file   (optional) CA bundle path used when ssl_verify is true
class Puppet::Transport::ProxmoxVirtualEnvironment
  # Seconds to wait for the TCP and TLS connection to the API.
  OPEN_TIMEOUT = 10
  # Seconds to wait for a response once a request has been sent.
  READ_TIMEOUT = 60
  # Connection-level errors that indicate a stale keep-alive socket. On an
  # idempotent GET these are retried once against a fresh connection.
  RETRYABLE_CONNECTION_ERRORS = [EOFError, Errno::ECONNRESET, Errno::EPIPE, IOError].freeze

  def initialize(context, connection_info)
    @host         = connection_info[:host]
    @port         = connection_info[:port] || 8006
    @token_id     = connection_info[:token_id]
    ts = connection_info[:token_secret]
    @token_secret = ts.respond_to?(:unwrap) ? ts.unwrap : ts.to_s
    @ssl_verify   = connection_info.fetch(:ssl_verify, true)
    @ssl_ca_file  = connection_info[:ssl_ca_file]
    validate_connection_info!
    context.debug("Initialized PVE transport for #{@host}:#{@port}")
  end

  def get(context, path, query = nil)
    request(context, Net::HTTP::Get, path, nil, query)
  end

  def post(context, path, body = {}, query = nil)
    request(context, Net::HTTP::Post, path, body, query)
  end

  def put(context, path, body = {}, query = nil)
    request(context, Net::HTTP::Put, path, body, query)
  end

  def delete(context, path, body = nil, query = nil)
    request(context, Net::HTTP::Delete, path, body, query)
  end

  def call(context, method, path, body: nil, query: nil, path_params: nil)
    expanded_path = expand_path(path, path_params || {})
    request(context, http_method_class(method), expanded_path, body, query)
  end

  def expand_path(path, path_params)
    path_params.reduce(path) do |expanded, (key, value)|
      expanded.gsub("{#{key}}", URI::DEFAULT_PARSER.escape(value.to_s, %r{[^A-Za-z0-9_.~-]}))
    end
  end

  private

  def validate_connection_info!
    raise Puppet::ResourceError, "PVE transport config is missing a value for 'host'" if blank?(@host)
    raise Puppet::ResourceError, "PVE transport config is missing a value for 'token_id'" if blank?(@token_id)
    raise Puppet::ResourceError, "PVE transport config is missing a value for 'token_secret'" if blank?(@token_secret)
  end

  def blank?(value)
    value.nil? || value.to_s.empty?
  end

  def request(context, method_class, path, body = nil, query = nil)
    uri  = build_uri(path, query)
    req  = method_class.new(uri)
    req['Authorization'] = "PVEAPIToken=#{@token_id}=#{@token_secret}"
    req['Content-Type']  = 'application/json'
    req.body = body.to_json if body && !body.empty?

    context.debug("PVE API #{method_class::METHOD} #{uri.request_uri}")
    response = perform_request(context, req, method_class)
    handle_response(context, response, path)
  end

  # Perform the HTTP request, resetting and retrying once on a stale
  # keep-alive connection for idempotent GETs only. Non-idempotent methods
  # are never auto-retried; their memoized connection is reset and a clear
  # error is raised so the caller can decide how to proceed.
  def perform_request(context, req, method_class)
    retried = false
    begin
      http_connection.request(req)
    rescue *RETRYABLE_CONNECTION_ERRORS => error
      reset_http_connection
      if method_class == Net::HTTP::Get && !retried
        retried = true
        context.debug("Retrying idempotent GET after stale connection: #{error.class}")
        retry
      end
      raise Puppet::ResourceError,
            "PVE API connection error (#{error.class}): #{error.message}"
    end
  end

  def reset_http_connection
    @http_connection&.finish if @http_connection&.started?
  rescue IOError
    nil
  ensure
    @http_connection = nil
  end

  def build_uri(path, query)
    uri = URI("https://#{@host}:#{@port}/api2/json#{path}")
    uri.query = URI.encode_www_form(query) if query && !query.empty?
    uri
  end

  def http_method_class(method)
    {
      'GET'    => Net::HTTP::Get,
      'POST'   => Net::HTTP::Post,
      'PUT'    => Net::HTTP::Put,
      'DELETE' => Net::HTTP::Delete,
    }.fetch(method.to_s.upcase) do
      raise Puppet::ResourceError, "Unsupported PVE API method #{method}"
    end
  end

  def http_connection
    @http_connection ||= Net::HTTP.new(@host, @port).tap do |http|
      http.use_ssl      = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      if @ssl_verify
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.ca_file     = @ssl_ca_file if @ssl_ca_file
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http.start
    end
  end

  def handle_response(_context, response, path)
    code = response.code
    body = response.body
    unless code.to_i.between?(200, 299)
      raise Puppet::ResourceError,
            "PVE API error #{code} on #{path}: #{body}"
    end
    return nil if body.nil? || body.empty?

    begin
      parsed = JSON.parse(body)
    rescue JSON::ParserError
      raise Puppet::ResourceError, "PVE API returned a non-JSON response on #{path}"
    end
    (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed
  end
end
