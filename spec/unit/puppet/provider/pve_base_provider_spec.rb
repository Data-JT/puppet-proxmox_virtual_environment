# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'puppet/provider/pve_base_provider'

class Puppet::Provider::TestProvider < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'name'        => :name,
      'gc-schedule' => :gc_schedule,
      'enabled'     => :enabled,
      'delete'      => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:enabled]
  end
end

class Puppet::Provider::PropertyStringTestProvider < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'name'      => :name,
      'migration' => :migration,
    }
  end

  def self.property_string_attributes
    [:migration]
  end
end

class Puppet::Provider::IntegerTestProvider < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'name'        => :name,
      'max_workers' => :max_workers,
    }
  end

  def self.integer_attributes
    [:max_workers]
  end
end

class Puppet::Provider::BootstrapTestProvider < Puppet::Provider::PveBaseProvider
  attr_reader :updated

  def get(_context)
    [{ name: 'existing', ensure: 'present', enabled: false }]
  end

  def update(_context, name, should)
    @updated = [name, should]
  end
end

RSpec.describe Puppet::Provider::PveBaseProvider do
  subject(:provider) { Puppet::Provider::TestProvider.new }

  let(:mock_type) { instance_double('Puppet::ResourceApi::Type') }
  let(:context)   { instance_double('Puppet::ResourceApi::BaseContext', type: mock_type) }

  before(:each) do
    allow(Puppet).to receive(:[]).with(:certname).and_return('pve01.example.com')
  end

  describe '#pve_to_puppet' do
    it 'maps PVE string keys to Puppet symbol keys' do
      result = provider.pve_to_puppet('name' => 'mystore', 'gc-schedule' => 'daily')
      expect(result).to include(name: 'mystore', gc_schedule: 'daily')
    end

    it 'ignores keys not in attribute_map' do
      result = provider.pve_to_puppet('name' => 'mystore', 'unknown-key' => 'value')
      expect(result).not_to have_key(:unknown_key)
      expect(result).not_to have_key('unknown-key')
    end

    it 'converts integer 1 to true for boolean attributes' do
      result = provider.pve_to_puppet('enabled' => 1)
      expect(result[:enabled]).to be true
    end

    it 'converts integer 0 to false for boolean attributes' do
      result = provider.pve_to_puppet('enabled' => 0)
      expect(result[:enabled]).to be false
    end

    it 'does not include keys absent from the input hash' do
      result = provider.pve_to_puppet('name' => 'only-name')
      expect(result).not_to have_key(:gc_schedule)
      expect(result).not_to have_key(:enabled)
    end
  end

  describe '#puppet_to_pve' do
    it 'maps Puppet symbol keys to PVE string keys' do
      result = provider.puppet_to_pve(name: 'mystore', gc_schedule: 'daily')
      expect(result).to include('name' => 'mystore', 'gc-schedule' => 'daily')
    end

    it 'strips nil values' do
      result = provider.puppet_to_pve(name: 'mystore', gc_schedule: nil)
      expect(result).not_to have_key('gc-schedule')
    end

    it 'keeps true as a boolean for PVE JSON bodies' do
      result = provider.puppet_to_pve(enabled: true)
      expect(result['enabled']).to eq(true)
    end

    it 'converts Puppet :true symbols to boolean true for PVE JSON bodies' do
      result = provider.puppet_to_pve(enabled: :true)
      expect(result['enabled']).to eq(true)
    end

    it 'keeps false as a boolean for PVE JSON bodies' do
      result = provider.puppet_to_pve(enabled: false)
      expect(result['enabled']).to eq(false)
    end

    it 'converts Puppet :false symbols to boolean false for PVE JSON bodies' do
      result = provider.puppet_to_pve(enabled: :false)
      expect(result['enabled']).to eq(false)
    end

    it 'unwraps a Sensitive value' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('s3cr3t')
      result = provider.puppet_to_pve(name: sensitive)
      expect(result['name']).to eq('s3cr3t')
    end
  end

  describe '#request_body' do
    before(:each) { allow(mock_type).to receive(:namevars).and_return([:name]) }

    it 'drops :ensure from the body' do
      should = { name: 'mystore', gc_schedule: 'daily', ensure: 'present' }
      result = provider.request_body(should)
      expect(result).not_to have_key(:ensure)
      expect(result).not_to have_key('ensure')
    end

    it 'retains the namevar in create request bodies' do
      should = { name: 'mystore', ensure: 'present' }
      result = provider.request_body(should)
      expect(result).to include('name' => 'mystore')
    end

    it 'drops the namevar from update request bodies' do
      should = { name: 'mystore', gc_schedule: 'daily', ensure: 'present' }
      result = provider.update_body(context, should)
      expect(result).not_to have_key('name')
      expect(result).to include('gc-schedule' => 'daily')
    end

    it 'does not mutate the original should hash' do
      should = { name: 'mystore', ensure: 'present' }
      original = should.dup
      provider.update_body(context, should)
      expect(should).to eq(original)
    end

    it 'normalizes delete_properties to a comma-separated PVE delete parameter' do
      result = provider.update_body(
        context,
        { name: 'mystore', delete_properties: ['comment', 'enabled'], ensure: 'present' },
      )
      expect(result['delete']).to eq('comment,enabled')
    end
  end

  describe '#create_body' do
    before(:each) { allow(mock_type).to receive(:namevars).and_return([:name]) }

    it 'retains the namevar in create request bodies' do
      result = provider.create_body(context, { name: 'mystore', gc_schedule: 'daily', ensure: 'present' })
      expect(result).to include('name' => 'mystore', 'gc-schedule' => 'daily')
    end

    it 'never sends a delete parameter even when delete_properties are declared' do
      result = provider.create_body(
        context,
        { name: 'mystore', delete_properties: ['gc-schedule', 'enabled'], ensure: 'present' },
      )
      expect(result).not_to have_key('delete')
    end
  end

  describe 'transport bootstrap' do
    it 'treats a missing managed transport config as empty during discovery' do
      allow(provider).to receive(:pve_transport)
        .and_raise(Puppet::Provider::PveBaseProvider::TransportConfigMissingError, 'PVE transport config not found at /tmp/pve_transport.yaml; apply class')

      expect(provider.transport_get(context, '/storage')).to eq([])
    end

    it 'does not swallow unrelated ResourceErrors during discovery' do
      allow(provider).to receive(:pve_transport)
        .and_raise(Puppet::ResourceError, 'some other failure')

      expect { provider.transport_get(context, '/storage') }.to raise_error(Puppet::ResourceError, 'some other failure')
    end

    it 'refreshes actual state before applying changes after first-run bootstrap' do
      bootstrap_provider = Puppet::Provider::BootstrapTestProvider.new
      bootstrap_provider.instance_variable_set(:@transport_config_missing, true)
      allow(Puppet::Provider::BootstrapTestProvider).to receive(:load_transport_config)
        .and_return(cluster_manager: 'pve01.example.com')
      bootstrap_type = instance_double(
        'Puppet::ResourceApi::Type',
        namevars: [:name],
        ensurable?: true,
        feature?: false,
        attributes: {},
      )
      bootstrap_context = instance_double('Puppet::ResourceApi::BaseContext', type: bootstrap_type)
      allow(bootstrap_context).to receive(:updating).and_yield
      allow(bootstrap_context).to receive(:creating).and_yield
      allow(bootstrap_context).to receive(:deleting).and_yield
      allow(bootstrap_type).to receive(:check_schema)

      bootstrap_provider.set(
        bootstrap_context,
        'existing' => { should: { name: 'existing', ensure: 'present', enabled: true } },
      )

      expect(bootstrap_provider.updated).to eq(['existing', { name: 'existing', ensure: 'present', enabled: true }])
    end
  end

  describe 'cluster manager write guard' do
    let(:changes) { { 'resource' => { should: { name: 'resource', ensure: 'present' } } } }

    it 'permits writes on the configured cluster manager' do
      allow(Puppet::Provider::TestProvider).to receive(:load_transport_config)
        .and_return(cluster_manager: 'pve01.example.com')

      expect { provider.send(:assert_cluster_manager!) }.not_to raise_error
    end

    it 'rejects writes on another Puppet node' do
      allow(Puppet::Provider::TestProvider).to receive(:load_transport_config)
        .and_return(cluster_manager: 'pve01.example.com')
      allow(Puppet).to receive(:[]).with(:certname).and_return('pve02.example.com')

      expect { provider.set(context, changes) }.to raise_error(
        Puppet::ResourceError,
        %r{restricted to cluster manager pve01\.example\.com; current Puppet certname is pve02\.example\.com},
      )
    end

    it 'rejects writes when no cluster manager is configured' do
      allow(Puppet::Provider::TestProvider).to receive(:load_transport_config).and_return({})

      expect { provider.set(context, changes) }.to raise_error(
        Puppet::ResourceError,
        %r{has no cluster_manager; refusing PVE API changes},
      )
    end
  end

  describe '.build_transport' do
    it 'raises a helpful error when the transport config file is missing' do
      allow(Puppet::Provider::TestProvider).to receive(:config_path).and_return('/nonexistent/dir/pve_transport.yaml')

      expect { Puppet::Provider::TestProvider.build_transport(context) }.to raise_error(
        Puppet::ResourceError,
        'PVE transport config not found at /nonexistent/dir/pve_transport.yaml; ' \
        'ensure the proxmox_virtual_environment class is applied before managing PVE resources',
      )
    end

    it 'loads the YAML config file and builds a transport from its symbolized settings' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'pve_transport.yaml')
        File.write(path, { 'host' => 'pve.example.com', 'token_id' => 'id', 'token_secret' => 'secret', 'cluster_manager' => 'pve01.example.com' }.to_yaml)
        allow(Puppet::Provider::TestProvider).to receive(:config_path).and_return(path)
        allow(context).to receive(:debug)

        transport = Puppet::Provider::TestProvider.build_transport(context)

        expect(transport).to be_a(Puppet::Transport::ProxmoxVirtualEnvironment)
        expect(transport.instance_variable_get(:@host)).to eq('pve.example.com')
      end
    end

    # The class links the discovery path to a relocated config_file.
    it 'follows a symlink at the discovery path to a relocated config_file' do
      Dir.mktmpdir do |dir|
        target = File.join(dir, 'elsewhere.yaml')
        link = File.join(dir, 'pve_transport.yaml')
        File.write(target, { 'host' => 'linked.example.com', 'token_id' => 'id', 'token_secret' => 'secret', 'cluster_manager' => 'pve01.example.com' }.to_yaml)
        File.symlink(target, link)
        allow(Puppet::Provider::TestProvider).to receive(:config_path).and_return(link)
        allow(context).to receive(:debug)

        transport = Puppet::Provider::TestProvider.build_transport(context)

        expect(transport.instance_variable_get(:@host)).to eq('linked.example.com')
        expect(Puppet::Provider::TestProvider.load_transport_config[:cluster_manager]).to eq('pve01.example.com')
      end
    end
  end

  describe '.load_transport_config' do
    it 'raises a clear error when the config file is empty' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'pve_transport.yaml')
        File.write(path, '')
        allow(Puppet::Provider::TestProvider).to receive(:config_path).and_return(path)

        expect { Puppet::Provider::TestProvider.load_transport_config }.to raise_error(
          Puppet::ResourceError,
          "PVE transport config at #{path} is empty or invalid",
        )
      end
    end

    it 'raises a clear error when the config is not a Hash' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'pve_transport.yaml')
        File.write(path, ['just', 'a', 'list'].to_yaml)
        allow(Puppet::Provider::TestProvider).to receive(:config_path).and_return(path)

        expect { Puppet::Provider::TestProvider.load_transport_config }.to raise_error(
          Puppet::ResourceError,
          "PVE transport config at #{path} is empty or invalid",
        )
      end
    end
  end

  describe '#pve_transport' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:config_path) { File.join(tmpdir, 'pve_transport.yaml') }

    before(:each) do
      File.write(config_path, { 'host' => 'pve.example.com', 'token_id' => 'id', 'token_secret' => 'secret', 'cluster_manager' => 'pve01.example.com' }.to_yaml)
      allow(Puppet::Provider::TestProvider).to receive(:config_path).and_return(config_path)
      allow(context).to receive(:debug)
    end

    after(:each) { FileUtils.remove_entry(tmpdir) }

    it 'builds the transport once and reuses it while the config file is unchanged' do
      first = provider.pve_transport(context)
      second = provider.pve_transport(context)

      expect(second).to be(first)
    end

    it 'rebuilds the transport when the config file is modified' do
      first = provider.pve_transport(context)

      File.write(config_path, { 'host' => 'changed.example.com', 'token_id' => 'id', 'token_secret' => 'secret', 'cluster_manager' => 'pve01.example.com' }.to_yaml)
      File.utime(Time.now + 1, Time.now + 1, config_path)

      second = provider.pve_transport(context)

      expect(second).not_to be(first)
      expect(second.instance_variable_get(:@host)).to eq('changed.example.com')
    end
  end

  describe '#insync?' do
    it 'requests deletion only while the targeted property still exists' do
      should = { delete_properties: ['gc-schedule'] }
      expect(provider.insync?(context, 'mystore', :delete_properties, { gc_schedule: 'daily' }, should)).to be(false)
      expect(provider.insync?(context, 'mystore', :delete_properties, {}, should)).to be(true)
    end

    it 'rejects deletion of properties the provider cannot observe' do
      expect {
        provider.insync?(context, 'mystore', :delete_properties, {}, delete_properties: ['unknown'])
      }.to raise_error(Puppet::ResourceError, %r{Cannot observe})
    end
  end

  describe 'secret attributes' do
    let(:secret_provider_class) do
      Class.new(Puppet::Provider::PveBaseProvider) do
        def self.secret_attributes
          [:password]
        end

        def stub_stored(value)
          @stored = value
        end

        def stored_secret(_title, _attribute_name)
          @stored
        end
      end
    end
    let(:secret_provider) { secret_provider_class.new }

    before(:each) { allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:assert_available!) }

    it 'is in sync when the stored secret equals the declared one' do
      secret_provider.stub_stored('hunter2')
      expect(secret_provider.insync?(context, 'x', :password, {}, password: 'hunter2')).to be(true)
    end

    it 'is out of sync when the stored secret differs' do
      secret_provider.stub_stored('old')
      expect(secret_provider.insync?(context, 'x', :password, {}, password: 'hunter2')).to be(false)
    end

    it 'is out of sync when PVE holds no secret at all' do
      secret_provider.stub_stored(nil)
      expect(secret_provider.insync?(context, 'x', :password, {}, password: 'hunter2')).to be(false)
    end

    it 'unwraps a Sensitive declared value' do
      secret_provider.stub_stored('hunter2')
      wrapped = Puppet::Pops::Types::PSensitiveType::Sensitive.new('hunter2')
      expect(secret_provider.insync?(context, 'x', :password, {}, password: wrapped)).to be(true)
    end

    it 'is in sync when the secret is not declared this run' do
      secret_provider.stub_stored('anything')
      expect(secret_provider.insync?(context, 'x', :password, {}, {})).to be(true)
    end

    it 'fails closed when the store cannot be read' do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore)
        .to receive(:assert_available!).and_raise(Puppet::ResourceError, 'not readable')
      secret_provider.stub_stored('hunter2')
      expect { secret_provider.insync?(context, 'x', :password, {}, password: 'hunter2') }
        .to raise_error(Puppet::ResourceError, %r{not readable})
    end

    it 'does not consult the store for an undeclared secret' do
      expect(PuppetX::ProxmoxVirtualEnvironment::SecretStore).not_to receive(:assert_available!)
      secret_provider.insync?(context, 'x', :password, {}, {})
    end

    it 'raises a clear error when a provider declares secrets but has no stored_secret' do
      incomplete_class = Class.new(Puppet::Provider::PveBaseProvider) do
        def self.secret_attributes
          [:password]
        end
      end
      incomplete = incomplete_class.new
      expect { incomplete.insync?(context, 'x', :password, {}, password: 'p') }
        .to raise_error(NotImplementedError, %r{stored_secret})
    end

    it 'leaves non-secret attributes to the existing dispatch' do
      expect(secret_provider.insync?(context, 'x', :other, {}, other: 'v')).to be_nil
    end
  end

  describe '#unordered_csv_insync?' do
    it 'treats comma-separated lists as equal regardless of order' do
      expect(provider.unordered_csv_insync?('backup,vztmpl,iso', 'vztmpl,backup,iso')).to be(true)
    end

    it 'detects an actual difference in membership' do
      expect(provider.unordered_csv_insync?('backup,vztmpl', 'backup,vztmpl,iso')).to be(false)
    end
  end

  # PVE returns property strings inconsistently on the SAME request: on
  # GET /cluster/options 'bwlimit' is a String while 'migration' is an expanded
  # Hash. An unconverted Hash fails the Optional[String] type schema and makes
  # the resource unmanageable on every run.
  describe 'property strings' do
    describe '#serialize_property_string' do
      it 'renders an expanded Hash as a property string with sorted keys' do
        expect(provider.serialize_property_string('type' => 'secure', 'network' => '192.0.2.0/24'))
          .to eq('network=192.0.2.0/24,type=secure')
      end

      it 'passes an already-String value through untouched' do
        expect(provider.serialize_property_string('migration=500000')).to eq('migration=500000')
      end

      it 'leaves nil alone' do
        expect(provider.serialize_property_string(nil)).to be_nil
      end
    end

    describe '#property_string_insync?' do
      it 'ignores key order, which PVE does not preserve' do
        expect(provider.property_string_insync?('network=192.0.2.0/24,type=secure',
                                                'type=secure,network=192.0.2.0/24')).to be(true)
      end

      it 'compares an expanded Hash against the declared string form' do
        expect(provider.property_string_insync?({ 'type' => 'secure', 'network' => '10.0.0.0/24' },
                                                'type=secure,network=10.0.0.0/24')).to be(true)
      end

      it 'detects a changed value' do
        expect(provider.property_string_insync?('type=secure,network=192.0.2.0/24',
                                                'type=secure,network=198.51.100.0/24')).to be(false)
      end

      it 'tolerates whitespace around separators' do
        expect(provider.property_string_insync?('type=secure, network=10.0.0.0/24',
                                                'type=secure,network=10.0.0.0/24')).to be(true)
      end

      it 'treats an unset current value as out of sync with a declared one' do
        expect(provider.property_string_insync?(nil, 'type=secure')).to be(false)
      end

      it 'treats both unset as in sync' do
        expect(provider.property_string_insync?(nil, nil)).to be(true)
      end
    end

    describe '#pve_to_puppet' do
      let(:string_provider) { Puppet::Provider::PropertyStringTestProvider.new }

      it 'normalises a Hash-valued property string on read' do
        expect(string_provider.pve_to_puppet('migration' => { 'type' => 'secure', 'network' => '10.0.0.0/24' }))
          .to eq(migration: 'network=10.0.0.0/24,type=secure')
      end

      it 'leaves attributes not declared as property strings untouched' do
        expect(string_provider.pve_to_puppet('name' => 'datacenter')).to eq(name: 'datacenter')
      end
    end
  end

  describe 'integer attributes' do
    let(:integer_provider) { Puppet::Provider::IntegerTestProvider.new }

    # PVE returns max_workers as "2" while the type declares Optional[Integer],
    # which fails schema validation on every run once the value is set.
    it 'coerces a String-valued integer on read' do
      expect(integer_provider.pve_to_puppet('max_workers' => '2')).to eq(max_workers: 2)
    end

    it 'leaves an already-Integer value untouched' do
      expect(integer_provider.pve_to_puppet('max_workers' => 2)).to eq(max_workers: 2)
    end

    it 'handles negative values' do
      expect(integer_provider.pve_to_puppet('max_workers' => '-1')).to eq(max_workers: -1)
    end

    # String#to_i would turn these into 0 and hide a genuine API change behind a
    # plausible-looking value. Better to let the schema error surface.
    it 'leaves a non-numeric value alone rather than coercing it to 0' do
      expect(integer_provider.pve_to_puppet('max_workers' => 'auto')).to eq(max_workers: 'auto')
      expect(integer_provider.pve_to_puppet('max_workers' => '2x')).to eq(max_workers: '2x')
      expect(integer_provider.pve_to_puppet('max_workers' => '')).to eq(max_workers: '')
    end

    it 'leaves attributes not declared as integers untouched' do
      expect(integer_provider.pve_to_puppet('name' => 'datacenter')).to eq(name: 'datacenter')
    end
  end

  describe 'immutable attributes' do
    it 'rejects updates that change an init_only attribute' do
      immutable_type = instance_double(
        'Puppet::ResourceApi::Type',
        attributes: { type: { behaviour: :init_only } },
      )
      immutable_context = instance_double('Puppet::ResourceApi::BaseContext', type: immutable_type)
      allow(Puppet::Provider::TestProvider).to receive(:load_transport_config)
        .and_return(cluster_manager: 'pve01.example.com')

      expect {
        provider.set(
          immutable_context,
          'resource' => {
            is: { ensure: 'present', type: 'old' },
            should: { ensure: 'present', type: 'new' },
          },
        )
      }.to raise_error(Puppet::ResourceError, %r{Cannot change immutable PVE attributes: type})
    end
  end
end
