# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../tools/pve_hiera_import'

RSpec.describe 'pve_hiera_import' do
  describe '.normalize_boolean' do
    it 'normalizes truthy PVE values to true' do
      expect(normalize_boolean(true)).to be(true)
      expect(normalize_boolean(1)).to be(true)
      expect(normalize_boolean('1')).to be(true)
      expect(normalize_boolean('true')).to be(true)
    end

    it 'normalizes falsy PVE values to false' do
      expect(normalize_boolean(false)).to be(false)
      expect(normalize_boolean(0)).to be(false)
      expect(normalize_boolean('0')).to be(false)
      expect(normalize_boolean('false')).to be(false)
    end

    it 'passes through values it does not recognize' do
      expect(normalize_boolean('maybe')).to eq('maybe')
    end
  end

  describe '.normalize_entry' do
    let(:mapping) { RESOURCE_MAPPINGS.fetch(:storages) }

    it 'maps known API fields to their Puppet attribute names' do
      attributes = normalize_entry({ 'type' => 'dir', 'path' => '/mnt/data' }, mapping)
      expect(attributes).to include('ensure' => 'present', 'type' => 'dir', 'path' => '/mnt/data')
    end

    it 'ignores fields that are not part of the mapping' do
      attributes = normalize_entry({ 'type' => 'dir', 'unknown-field' => 'value' }, mapping)
      expect(attributes).not_to have_key('unknown_field')
      expect(attributes).not_to have_key('unknown-field')
    end

    it 'drops fields with a nil value' do
      attributes = normalize_entry({ 'type' => 'dir', 'shared' => nil }, mapping)
      expect(attributes).not_to have_key('shared')
    end

    it 'normalizes boolean fields declared in the mapping' do
      attributes = normalize_entry({ 'type' => 'dir', 'shared' => 1, 'disable' => '0' }, mapping)
      expect(attributes).to include('shared' => true, 'disable' => false)
    end

    it 'leaves non-boolean fields untouched' do
      attributes = normalize_entry({ 'type' => 'dir', 'pool' => 'rbd-pool' }, mapping)
      expect(attributes).to include('pool' => 'rbd-pool')
    end
  end

  describe '.resource_key' do
    it 'reads the configured key field for plain mappings' do
      mapping = RESOURCE_MAPPINGS.fetch(:storages)
      expect(resource_key({ 'storage' => 'local' }, mapping)).to eq('local')
    end

    it 'builds a composite key via key_proc for ACL entries' do
      mapping = RESOURCE_MAPPINGS.fetch(:acls)
      entry = { 'path' => '/vms/100', 'ugid' => 'admins', 'roleid' => 'PVEAdmin' }
      expect(resource_key(entry, mapping)).to eq('/vms/100|admins|PVEAdmin')
    end

    it 'falls back to the role field when roleid is absent' do
      mapping = RESOURCE_MAPPINGS.fetch(:acls)
      entry = { 'path' => '/vms/100', 'ugid' => 'admins', 'role' => 'PVEAdmin' }
      expect(resource_key(entry, mapping)).to eq('/vms/100|admins|PVEAdmin')
    end
  end

  describe '.load_transport_config' do
    it 'loads YAML and symbolizes top-level keys' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'pve_transport.yaml')
        File.write(path, { 'host' => 'pve.example.com', 'port' => 8006 }.to_yaml)

        expect(load_transport_config(path)).to eq(host: 'pve.example.com', port: 8006)
      end
    end
  end

  describe '.parse_options' do
    it 'requires a token id and token secret' do
      expect { parse_options([]) }.to raise_error(OptionParser::MissingArgument, %r{--token-id})
    end

    it 'parses host, port and token options' do
      options = parse_options(['--host', 'pve.example.com', '--port', '8007', '--token-id', 'puppet@pve!puppet', '--token-secret', 's3cret'])
      expect(options).to include(host: 'pve.example.com', port: 8007, token_id: 'puppet@pve!puppet', token_secret: 's3cret')
    end

    it 'reads the token secret from a file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'token_secret')
        File.write(path, "s3cret\n")

        options = parse_options(['--token-id', 'puppet@pve!puppet', '--token-secret-file', path])
        expect(options[:token_secret]).to eq('s3cret')
      end
    end

    it 'disables SSL verification' do
      options = parse_options(['--token-id', 'id', '--token-secret', 'secret', '--no-ssl-verify'])
      expect(options[:ssl_verify]).to be(false)
    end

    it 'enables skip-errors and include-transport-parameters' do
      options = parse_options(['--token-id', 'id', '--token-secret', 'secret', '--skip-errors', '--include-transport-parameters'])
      expect(options[:skip_errors]).to be(true)
      expect(options[:include_transport_parameters]).to be(true)
    end

    it 'merges connection settings loaded from a transport config file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'pve_transport.yaml')
        File.write(path, { 'host' => 'from-config.example.com', 'token_id' => 'puppet@pve!puppet', 'token_secret' => 'from-config' }.to_yaml)

        options = parse_options(['--transport-config', path])
        expect(options).to include(host: 'from-config.example.com', token_id: 'puppet@pve!puppet', token_secret: 'from-config')
      end
    end
  end

  describe '.build_hiera_data' do
    let(:client) { instance_double(PveApiClient) }
    let(:options) { DEFAULT_OPTIONS.merge(token_id: 'id', token_secret: 'secret') }

    it 'builds resources keyed by the resource id from API responses' do
      allow(client).to receive(:get).and_return([])
      allow(client).to receive(:get).with('/storage').and_return([{ 'storage' => 'local', 'type' => 'dir' }])

      data = build_hiera_data(client, options)

      expect(data['proxmox_virtual_environment::resources::storages']).to eq(
        'local' => { 'ensure' => 'present', 'type' => 'dir' },
      )
    end

    it 'omits resource keys for endpoints that returned no data' do
      allow(client).to receive(:get).and_return([])

      data = build_hiera_data(client, options)

      expect(data).not_to have_key('proxmox_virtual_environment::resources::storages')
      expect(data).not_to have_key('proxmox_virtual_environment::resources::users')
    end

    it 'raises when an endpoint fails and skip_errors is disabled' do
      allow(client).to receive(:get).and_raise('boom')

      expect { build_hiera_data(client, options) }.to raise_error('boom')
    end

    it 'warns and continues when an endpoint fails and skip_errors is enabled' do
      allow(client).to receive(:get).and_raise('boom')

      expect { build_hiera_data(client, options.merge(skip_errors: true)) }.to output(%r{Skipping /storage: boom}).to_stderr
    end

    it 'does not include transport parameters by default' do
      allow(client).to receive(:get).and_return([])

      data = build_hiera_data(client, options)

      expect(data).not_to have_key('proxmox_virtual_environment::host')
      expect(data).not_to have_key('lookup_options')
    end

    it 'emits transport class parameters when requested, masking the token secret' do
      allow(client).to receive(:get).and_return([])

      data = build_hiera_data(client, options.merge(
                                          include_transport_parameters: true,
                                          host: 'pve.example.com',
                                          port: 8006,
                                          ssl_ca_file: '/etc/ssl/pve-ca.pem',
                                        ))

      expect(data['proxmox_virtual_environment::host']).to eq('pve.example.com')
      expect(data['proxmox_virtual_environment::port']).to eq(8006)
      expect(data['proxmox_virtual_environment::ssl_ca_file']).to eq('/etc/ssl/pve-ca.pem')
      expect(data['proxmox_virtual_environment::token_id']).to eq('id')
      expect(data['proxmox_virtual_environment::token_secret']).to eq('CHANGE_ME_TOKEN_SECRET')
      expect(data['lookup_options']).to eq(
        'proxmox_virtual_environment::token_secret' => { 'convert_to' => 'Sensitive' },
      )
    end

    it 'produces data that serializes to YAML' do
      allow(client).to receive(:get).and_return([])
      allow(client).to receive(:get).with('/storage').and_return([{ 'storage' => 'local', 'type' => 'dir', 'shared' => 1 }])

      yaml = build_hiera_data(client, options).to_yaml
      reloaded = YAML.safe_load(yaml)

      expect(reloaded['proxmox_virtual_environment::resources::storages']).to eq(
        'local' => { 'ensure' => 'present', 'type' => 'dir', 'shared' => true },
      )
    end
  end

  describe '.run' do
    let(:client) { instance_double(PveApiClient) }

    before(:each) do
      allow(PveApiClient).to receive(:new).and_return(client)
      allow(client).to receive(:get).and_return([])
    end

    it 'writes the output file with 0600 permissions' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'out.yaml')
        run(['--token-id', 'id', '--token-secret', 'secret', '--output', path])

        expect('%o' % (File.stat(path).mode & 0o777)).to eq('600')
      end
    end

    it 'prints a friendly error and exits 1 for unexpected errors instead of a backtrace' do
      allow(PveApiClient).to receive(:new).and_raise(StandardError, 'boom')

      expect {
        expect { run(['--token-id', 'id', '--token-secret', 'secret']) }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      }.to output("error: boom\n").to_stderr
    end
  end
end
