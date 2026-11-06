# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_base_provider'
require 'puppet/provider/pve_datacenter_config/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveDatacenterConfig::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:name]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
  end

  describe '#get' do
    it 'returns a single resource titled datacenter and splits registered-tags on semicolons' do
      allow(transport).to receive(:get).with(context, '/cluster/options').and_return(
        'keyboard' => 'de', 'mac_prefix' => 'BC:24:11', 'description' => '',
        'registered-tags' => 'debian;ubuntu;template'
      )
      result = provider.get(context)
      expect(result).to contain_exactly(
        hash_including(
          name: 'datacenter', keyboard: 'de', mac_prefix: 'BC:24:11', description: '',
          registered_tags: ['debian', 'ubuntu', 'template'], ensure: 'present'
        ),
      )
    end

    it 'returns an empty registered_tags array when unset' do
      allow(transport).to receive(:get).with(context, '/cluster/options').and_return({})
      expect(provider.get(context)).to contain_exactly(hash_including(name: 'datacenter', registered_tags: []))
    end

    it 'tolerates transport_get returning [] when the managed transport config is missing' do
      allow(transport).to receive(:get).with(context, '/cluster/options').and_return([])
      expect(provider.get(context)).to contain_exactly(hash_including(name: 'datacenter', registered_tags: []))
    end

    it 'chomps a trailing newline from the description' do
      allow(transport).to receive(:get).with(context, '/cluster/options').and_return('description' => "Managed\n")
      expect(provider.get(context)).to contain_exactly(hash_including(name: 'datacenter', description: 'Managed'))
    end

    it 'reads registered_tags from allowed-tags when PVE returns it as a JSON array (PVE >= 9.2)' do
      allow(transport).to receive(:get).with(context, '/cluster/options').and_return(
        'keyboard' => 'de', 'allowed-tags' => ['debian', 'ubuntu', 'template'],
      )
      result = provider.get(context)
      expect(result).to contain_exactly(hash_including(name: 'datacenter', registered_tags: ['debian', 'ubuntu', 'template']))
    end

    # PVE 9.2 returns BOTH keys, and they differ: 'allowed-tags' is the
    # registered set UNION every tag in use on a guest. Preferring it makes the
    # property unmanageable in both directions -- a used-but-unregistered tag
    # shows up in 'is' forever, so declaring it reads as false agreement and it
    # never gets written, while omitting it reads as drift and is rewritten on
    # every run. Regression test for pve-manager 9.2.6.
    it 'prefers registered-tags over allowed-tags when PVE returns both' do
      allow(transport).to receive(:get).with(context, '/cluster/options').and_return(
        'keyboard' => 'de',
        'registered-tags' => 'debian;ubuntu',
        'allowed-tags' => ['debian', 'ubuntu', 'in-use-but-not-registered'],
      )
      result = provider.get(context)
      expect(result).to contain_exactly(hash_including(name: 'datacenter', registered_tags: ['debian', 'ubuntu']))
    end

    # The API schema says semicolon-separated string and PUT accepts that, but
    # GET on PVE 9.2 hands back an Array. Splitting that raises
    # "undefined method `split' for an instance of Array" and the whole
    # resource fails to evaluate.
    it 'accepts registered-tags as an Array, the shape PVE 9.2 GET returns' do
      allow(transport).to receive(:get).with(context, '/cluster/options').and_return(
        'keyboard' => 'de',
        'registered-tags' => ['debian', 'ubuntu'],
        'allowed-tags' => ['debian', 'ubuntu', 'in-use-but-not-registered'],
      )
      result = provider.get(context)
      expect(result).to contain_exactly(hash_including(name: 'datacenter', registered_tags: ['debian', 'ubuntu']))
    end

    # Verbatim shape returned by GET /cluster/options on PVE 9.x: 'migration'
    # expanded to an object while 'bwlimit' stays a string, on the same request.
    # Before normalisation this failed with "Provider returned data that does
    # not match the Type Schema" on every run, leaving datacenter.cfg correct
    # on disk but the resource permanently unmanageable.
    it 'normalises a Hash-valued migration property string to Optional[String]' do
      allow(transport).to receive(:get).with(context, '/cluster/options').and_return(
        'keyboard' => 'de',
        'bwlimit' => 'migration=500000',
        'migration' => { 'network' => '192.0.2.0/24', 'type' => 'secure' },
      )
      expect(provider.get(context)).to contain_exactly(
        hash_including(
          name: 'datacenter',
          bwlimit: 'migration=500000',
          migration: 'network=192.0.2.0/24,type=secure',
        ),
      )
    end
  end

  describe '#insync?' do
    # PVE returns the keys in its own order, so the serialised read-back does
    # not textually match the declared value even when nothing has changed.
    it 'treats a reordered migration property string as in sync' do
      expect(
        provider.insync?(context, 'datacenter', :migration,
                         { migration: 'network=192.0.2.0/24,type=secure' },
                         { migration: 'type=secure,network=192.0.2.0/24' }),
      ).to be(true)
    end

    it 'still detects a genuinely changed migration network' do
      expect(
        provider.insync?(context, 'datacenter', :migration,
                         { migration: 'network=192.0.2.0/24,type=secure' },
                         { migration: 'type=secure,network=198.51.100.0/24' }),
      ).to be(false)
    end
  end

  describe '#create delegates to update' do
    it 'puts to /cluster/options' do
      should = { name: 'datacenter', keyboard: 'de', ensure: 'present' }
      expect(transport).to receive(:put).with(context, '/cluster/options', hash_including('keyboard' => 'de'))
      provider.create(context, 'datacenter', should)
    end
  end

  describe '#update' do
    it 'puts the body without the namevar to /cluster/options' do
      should = { name: 'datacenter', keyboard: 'de', mac_prefix: 'BC:24:11', ensure: 'present' }
      expect(transport).to receive(:put) do |_ctx, path, body|
        expect(path).to eq('/cluster/options')
        expect(body).to include('keyboard' => 'de', 'mac_prefix' => 'BC:24:11')
        expect(body).not_to have_key('name')
      end
      provider.update(context, 'datacenter', should)
    end

    it 'joins registered_tags with semicolons' do
      should = { name: 'datacenter', registered_tags: ['debian', 'ubuntu'], ensure: 'present' }
      expect(transport).to receive(:put).with(context, '/cluster/options', hash_including('registered-tags' => 'debian;ubuntu'))
      provider.update(context, 'datacenter', should)
    end
  end

  describe '#insync? for delete_properties' do
    it 'allows deleting registered-tags even though it is handled outside attribute_map' do
      should = { delete_properties: ['registered-tags'] }
      expect(provider.insync?(context, 'datacenter', :delete_properties, { registered_tags: ['debian'] }, should)).to be(false)
      expect(provider.insync?(context, 'datacenter', :delete_properties, { registered_tags: [] }, should)).to be(true)
    end

    it 'still rejects an unknown deleted property' do
      should = { delete_properties: ['bogus'] }
      expect { provider.insync?(context, 'datacenter', :delete_properties, { registered_tags: [] }, should) }
        .to raise_error(Puppet::ResourceError, %r{Cannot observe deleted PVE properties: bogus})
    end

    it 'accepts a mix of registered-tags and a mapped attribute' do
      should = { delete_properties: ['registered-tags', 'description'] }
      expect(provider.insync?(context, 'datacenter', :delete_properties, { registered_tags: [] }, should)).to be(true)
      expect(provider.insync?(context, 'datacenter', :delete_properties, { registered_tags: [], description: 'x' }, should)).to be(false)
    end
  end

  describe '#delete' do
    it 'raises because the datacenter config cannot be deleted' do
      expect { provider.delete(context, 'datacenter') }
        .to raise_error(Puppet::ResourceError, %r{cannot be deleted})
    end
  end
end
