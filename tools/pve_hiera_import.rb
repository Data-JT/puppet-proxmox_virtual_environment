#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'optparse'
require 'uri'
require 'yaml'

RESOURCE_MAPPINGS = {
  storages: {
    endpoint: '/storage',
    key:      'storage',
    fields:   {
      'type'                   => 'type',
      'content'                => 'content',
      'path'                   => 'path',
      'server'                 => 'server',
      'export'                 => 'nfs_export',
      'share'                  => 'share',
      'portal'                 => 'portal',
      'target'                 => 'target',
      'vgname'                 => 'vgname',
      'thinpool'               => 'thinpool',
      'pool'                   => 'pool',
      'datastore'              => 'datastore',
      'username'               => 'username',
      'nodes'                  => 'nodes',
      'disable'                => 'disable',
      'shared'                 => 'shared',
      'prune-backups'          => 'prune_backups',
      'max-protected-backups'  => 'max_protected_backups',
      'namespace'              => 'namespace',
      'fingerprint'            => 'fingerprint',
      'skip-cert-verification' => 'skip_cert_verification',
      'options'                => 'options',
      'mountpoint'             => 'mountpoint',
      'subdir'                 => 'subdir',
    },
    booleans: ['disable', 'shared', 'skip-cert-verification'],
  },
  users: {
    endpoint: '/access/users',
    key:      'userid',
    fields:   {
      'comment'   => 'comment',
      'email'     => 'email',
      'enable'    => 'enable',
      'expire'    => 'expire',
      'firstname' => 'firstname',
      'groups'    => 'groups',
      'keys'      => 'keys',
      'lastname'  => 'lastname',
    },
    booleans: ['enable'],
  },
  acls: {
    endpoint: '/access/acl',
    key_proc: ->(entry) {
      role = entry['roleid'] || entry['role']
      "#{entry.fetch('path')}|#{entry.fetch('ugid')}|#{role}"
    },
    fields:   {
      'propagate' => 'propagate',
    },
    booleans: ['propagate'],
  },
  backup_jobs: {
    endpoint: '/cluster/backup',
    key:      'id',
    fields:   {
      'enabled'           => 'enabled',
      'schedule'          => 'job_schedule',
      'storage'           => 'storage',
      'mode'              => 'mode',
      'all'               => 'all',
      'vmid'              => 'vmid',
      'exclude'           => 'exclude',
      'node'              => 'node',
      'pool'              => 'pool',
      'compress'          => 'compress',
      'prune-backups'     => 'prune_backups',
      'mailto'            => 'mailto',
      'mailnotification'  => 'mailnotification',
      'notification-mode' => 'notification_mode',
      'notes-template'    => 'notes_template',
      'protected'         => 'protected',
      'repeat-missed'     => 'repeat_missed',
      'bwlimit'           => 'bwlimit',
      'comment'           => 'comment',
    },
    booleans: ['enabled', 'all', 'protected', 'repeat-missed'],
  },
}.freeze

DEFAULT_OPTIONS = {
  host:                         'localhost',
  port:                         8006,
  ssl_verify:                   true,
  skip_errors:                  false,
  include_transport_parameters: false,
}.freeze

# Minimal PVE REST client used by the Hiera importer.
class PveApiClient
  def initialize(options)
    @host         = options.fetch(:host)
    @port         = options.fetch(:port)
    @token_id     = options.fetch(:token_id)
    @token_secret = options.fetch(:token_secret)
    @ssl_verify   = options.fetch(:ssl_verify)
    @ssl_ca_file  = options[:ssl_ca_file]
  end

  def get(path)
    uri = URI("https://#{@host}:#{@port}/api2/json#{path}")
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "PVEAPIToken=#{@token_id}=#{@token_secret}"
    request['Content-Type'] = 'application/json'

    response = http.request(request)
    status = response.code.to_i
    response_body = response.body
    unless status.between?(200, 299)
      raise "PVE API error #{status} on #{path}: #{response_body}"
    end

    parsed = JSON.parse(response_body)
    (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed
  end

  private

  def http
    @http ||= Net::HTTP.new(@host, @port).tap do |connection|
      connection.use_ssl = true
      connection.open_timeout = 10
      connection.read_timeout = 60
      if @ssl_verify
        connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
        connection.ca_file = @ssl_ca_file if @ssl_ca_file
      else
        connection.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
    end
  end
end

def normalize_boolean(value)
  return true if [true, 1, '1', 'true'].include?(value)
  return false if [false, 0, '0', 'false'].include?(value)

  value
end

def normalize_entry(entry, mapping)
  attributes = { 'ensure' => 'present' }
  boolean_fields = mapping.fetch(:booleans, [])

  mapping.fetch(:fields).each do |api_field, puppet_field|
    next unless entry.key?(api_field)

    value = entry[api_field]
    next if value.nil?

    value = normalize_boolean(value) if boolean_fields.include?(api_field)
    attributes[puppet_field] = value
  end

  attributes
end

def resource_key(entry, mapping)
  return mapping.fetch(:key_proc).call(entry) if mapping.key?(:key_proc)

  entry.fetch(mapping.fetch(:key))
end

def build_hiera_data(client, options)
  data = {}

  if options[:include_transport_parameters]
    ssl_ca_file = options[:ssl_ca_file]
    data['lookup_options'] = {
      'proxmox_virtual_environment::token_secret' => {
        'convert_to' => 'Sensitive',
      },
    }
    data['proxmox_virtual_environment::host'] = options.fetch(:host)
    data['proxmox_virtual_environment::port'] = options.fetch(:port)
    data['proxmox_virtual_environment::ssl_verify'] = options.fetch(:ssl_verify)
    data['proxmox_virtual_environment::ssl_ca_file'] = ssl_ca_file if ssl_ca_file
    data['proxmox_virtual_environment::token_id'] = options.fetch(:token_id)
    data['proxmox_virtual_environment::token_secret'] = 'CHANGE_ME_TOKEN_SECRET'
  end

  RESOURCE_MAPPINGS.each do |name, mapping|
    resources = {}
    endpoint = mapping.fetch(:endpoint)
    begin
      Array(client.get(endpoint)).each do |entry|
        resources[resource_key(entry, mapping)] = normalize_entry(entry, mapping)
      end
    rescue StandardError => error
      raise unless options[:skip_errors]

      warn "Skipping #{endpoint}: #{error.message}"
    end

    data["proxmox_virtual_environment::resources::#{name}"] = resources unless resources.empty?
  end

  data
end

def load_transport_config(path)
  YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: false)
      .transform_keys(&:to_sym)
end

def parse_options(argv)
  options = DEFAULT_OPTIONS.dup

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: pve_hiera_import.rb [options]'

    opts.on('--transport-config PATH', 'Read connection settings from pve_transport.yaml') do |path|
      options.merge!(load_transport_config(path))
    end
    opts.on('--host HOST', 'PVE API host (default: localhost)') { |value| options[:host] = value }
    opts.on('--port PORT', Integer, 'PVE API port (default: 8006)') { |value| options[:port] = value }
    opts.on('--token-id TOKEN_ID', 'PVE API token ID') { |value| options[:token_id] = value }
    opts.on('--token-secret SECRET', 'PVE API token secret (visible in process lists; prefer --token-secret-file)') { |value| options[:token_secret] = value }
    opts.on('--token-secret-file PATH', 'Read PVE API token secret from a file') do |path|
      options[:token_secret] = File.read(path).strip
    end
    opts.on('--no-ssl-verify', 'Disable PVE TLS certificate verification') { options[:ssl_verify] = false }
    opts.on('--ssl-ca-file PATH', 'CA bundle path used for TLS verification') { |value| options[:ssl_ca_file] = value }
    opts.on('--output PATH', 'Write YAML to PATH instead of stdout') { |value| options[:output] = value }
    opts.on('--skip-errors', 'Warn and continue when an endpoint cannot be imported') { options[:skip_errors] = true }
    opts.on('--include-transport-parameters', 'Also emit proxmox_virtual_environment class parameters') do
      options[:include_transport_parameters] = true
    end
    opts.on('-h', '--help', 'Show this help') do
      puts opts
      exit
    end
  end

  parser.parse!(argv)

  missing = []
  missing << '--token-id' unless options[:token_id]
  missing << '--token-secret or --token-secret-file' unless options[:token_secret]
  raise OptionParser::MissingArgument, missing.join(', ') unless missing.empty?

  options
end

def run(argv)
  options = parse_options(argv)
  client = PveApiClient.new(options)
  yaml = build_hiera_data(client, options).to_yaml
  output = options[:output]

  if output
    File.write(output, yaml, perm: 0o600)
  else
    puts yaml
  end
rescue OptionParser::ParseError => error
  warn error.message
  exit 1
rescue StandardError => error
  warn "error: #{error.message}"
  exit 1
end

run(ARGV) if $PROGRAM_NAME == __FILE__
