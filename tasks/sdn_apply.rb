#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

# One-off apply of pending Proxmox VE SDN configuration.
#
# PUT /cluster/sdn regenerates /etc/network/interfaces.d/sdn on every cluster
# node and reloads networking there, so this is a maintenance-window operation.
# The pve_sdn_* Puppet types deliberately never call it; declaring
# pve_sdn_apply, or running this task, are the only ways it happens.
#
# Everything lives in a module so the top-level helpers of the other task in
# this module (pve_api_request) are not overwritten when both are loaded into
# the same Ruby process, which is what the spec suite does.
module PveSdnApplyTask
  APPLY_PATH = '/cluster/sdn'
  DRY_RUN_PATH = '/cluster/sdn/dry-run'
  POLL_INTERVAL = 2

  # Error raised on any PVE API failure. Carries structured details that are
  # surfaced in the Bolt `_error` object.
  class ApiError < StandardError
    attr_reader :details

    def initialize(msg, details: {})
      super(msg)
      @details = details
    end
  end

  module_function

  def task_input
    stdin = $stdin.read
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

  def connection(input)
    {
      'host'         => input.fetch('host'),
      'port'         => Integer(input.fetch('port', 8006)),
      'token_id'     => input.fetch('token_id'),
      'token_secret' => input.fetch('token_secret'),
      'ssl_verify'   => bool(input['ssl_verify'], default: true),
      'ssl_ca_file'  => input['ssl_ca_file'],
    }
  end

  def http_client(conn)
    http = Net::HTTP.new(conn['host'], conn['port'])
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 60
    http.verify_mode = conn['ssl_verify'] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    ca_file = conn['ssl_ca_file']
    http.ca_file = ca_file if ca_file && ca_file != ''
    http
  end

  def request(conn, method_class, path, query = nil)
    uri = URI("https://#{conn['host']}:#{conn['port']}/api2/json#{path}")
    uri.query = URI.encode_www_form(query) if query && !query.empty?

    req = method_class.new(uri)
    req['Authorization'] = "PVEAPIToken=#{conn['token_id']}=#{conn['token_secret']}"
    req['Content-Type'] = 'application/json'

    handle_response(http_client(conn).request(req), path)
  end

  # Single raise site for ApiError, so the structured details reach Bolt
  # without every call site constructing the exception by hand.
  def fail_api(message, details = {})
    raise ApiError.new(message, details: details)
  end

  def handle_response(response, path)
    status = response.code.to_i
    body = response.body

    fail_api("PVE API returned HTTP #{status} on #{path}", error_details(status, body)) unless status.between?(200, 299)

    parsed = (body.nil? || body.empty?) ? nil : JSON.parse(body)
    (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed
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

  def escape(value)
    URI::DEFAULT_PARSER.escape(value.to_s, %r{[^A-Za-z0-9_.~-]})
  end

  # Read-only preview of what an apply would change on one node, without
  # touching anything.
  def dry_run(conn, node)
    raise ArgumentError, 'dry_run requires a node' if node.nil? || node.to_s.empty?

    diff = request(conn, Net::HTTP::Get, DRY_RUN_PATH, 'node' => node)
    { 'success' => true, 'dry_run' => true, 'node' => node, 'diff' => diff }
  end

  def apply(conn, wait, timeout)
    upid = request(conn, Net::HTTP::Put, APPLY_PATH)
    return { 'success' => true, 'upid' => upid, 'waited' => false } unless wait

    result = wait_for_task(conn, upid, timeout)
    fail_api("SDN apply task #{upid} failed", result) unless result['exitstatus'] == 'OK'

    { 'success' => true, 'upid' => upid, 'waited' => true, 'exitstatus' => result['exitstatus'] }
  end

  def wait_for_task(conn, upid, timeout)
    node = upid.to_s.split(':')[1].to_s
    fail_api("PVE returned an unusable task ID: #{upid.inspect}") if node.empty?

    path = "/nodes/#{escape(node)}/tasks/#{escape(upid)}/status"
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      status = request(conn, Net::HTTP::Get, path)
      status = {} unless status.is_a?(Hash)
      return status if status['status'] == 'stopped'
      fail_api("Timed out after #{timeout}s waiting for SDN apply task #{upid}") if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep(POLL_INTERVAL)
    end
  end

  def sdn_apply(input)
    conn = connection(input)
    return dry_run(conn, input['node']) if bool(input['dry_run'], default: false)

    apply(conn, bool(input['wait'], default: true), Integer(input.fetch('timeout', 300)))
  end

  def run_task(input = nil)
    input ||= task_input
    puts JSON.pretty_generate(sdn_apply(input))
  rescue StandardError => error
    details = error.respond_to?(:details) ? error.details : {}
    puts JSON.pretty_generate(
      _error: {
        kind:    'proxmox_virtual_environment/sdn-apply-error',
        msg:     error.message,
        details: details,
      },
    )
    exit 1
  end
end

PveSdnApplyTask.run_task if $PROGRAM_NAME == __FILE__
