# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_sdn_zone/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveSdnZone::ProxmoxVirtualEnvironment do
  let(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:immutable_attributes) { { type: { behaviour: :init_only } } }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:zone], attributes: immutable_attributes) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
    allow(transport).to receive(:get).with(context, '/cluster/sdn/zones', { 'pending' => 1 }).and_return([])
  end

  describe 'get' do
    it 'reads the plain endpoint, not the pending one, for property values' do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/zones')
                                       .and_return([{ 'zone' => 'zone1', 'type' => 'vxlan', 'peers' => '10.0.0.1,10.0.0.2' }])

      result = provider.get(context).first
      expect(result).to include(zone: 'zone1', type: 'vxlan', peers: '10.0.0.1,10.0.0.2', ensure: 'present')
    end

    # A pending read returns the *running* values at the top level and the
    # configured ones in a nested 'pending' hash, so only 'state' is taken.
    it 'merges only the state from the pending read' do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/zones')
                                       .and_return([{ 'zone' => 'zone1', 'type' => 'vxlan', 'peers' => '10.0.0.3' }])
      allow(transport).to receive(:get).with(context, '/cluster/sdn/zones', { 'pending' => 1 })
                                       .and_return([{ 'zone' => 'zone1', 'peers' => '10.0.0.1', 'state' => 'changed', 'pending' => { 'peers' => '10.0.0.3' } }])

      result = provider.get(context).first
      expect(result[:pending_state]).to eq('changed')
      expect(result[:peers]).to eq('10.0.0.3')
    end

    it 'omits pending_state for an applied zone' do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/zones').and_return([{ 'zone' => 'zone1', 'type' => 'simple' }])
      expect(provider.get(context).first).not_to have_key(:pending_state)
    end

    it 'normalises a comma-separated secondary_controllers into the array the schema declares' do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/zones')
                                       .and_return([{ 'zone' => 'zone1', 'type' => 'evpn', 'secondary-controllers' => 'ctrl2,ctrl1' }])
      expect(provider.get(context).first[:secondary_controllers]).to eq(['ctrl1', 'ctrl2'])
    end
  end

  describe 'insync?' do
    # This is the case that drove the whole feature: moving a VXLAN zone's
    # peers to a new underlay. PVE hands the list back in its own order.
    it 'treats a reordered peers list as in sync' do
      expect(provider.insync?(context, 'zone1', :peers, { peers: '10.0.0.2,10.0.0.1' }, peers: '10.0.0.1,10.0.0.2')).to be(true)
    end

    it 'reports a genuinely changed peers list as out of sync' do
      expect(provider.insync?(context, 'zone1', :peers, { peers: '10.0.0.1,10.0.0.2' }, peers: '10.1.0.1,10.1.0.2')).to be(false)
    end

    it 'treats reordered exit nodes as in sync' do
      expect(provider.insync?(context, 'zone1', :exitnodes, { exitnodes: 'node2,node1' }, exitnodes: 'node1,node2')).to be(true)
    end

    it 'treats reordered secondary controllers as in sync' do
      expect(provider.insync?(context, 'zone1', :secondary_controllers, { secondary_controllers: ['b', 'a'] }, secondary_controllers: ['a', 'b'])).to be(true)
    end

    it 'falls back to the default comparison for an ordinary attribute' do
      expect(provider.insync?(context, 'zone1', :mtu, { mtu: 1450 }, mtu: 1500)).to be_nil
    end
  end

  describe 'create' do
    it 'posts the mapped body without a delete key' do
      expect(transport).to receive(:call).with(
        context, 'POST', '/cluster/sdn/zones',
        body: { 'zone' => 'zone1', 'type' => 'vxlan', 'peers' => '10.0.0.1,10.0.0.2', 'mtu' => 1450 },
        path_params: {}
      )

      provider.create(context, 'zone1', zone: 'zone1', type: 'vxlan', peers: '10.0.0.1,10.0.0.2', mtu: 1450, ensure: 'present')
    end

    it 'sends secondary controllers as a JSON array' do
      expect(transport).to receive(:call).with(
        context, 'POST', '/cluster/sdn/zones',
        body: { 'zone' => 'zone1', 'type' => 'evpn', 'controller' => 'ctrl1', 'secondary-controllers' => ['ctrl1', 'ctrl2'] },
        path_params: {}
      )

      provider.create(context, 'zone1', zone: 'zone1', type: 'evpn', controller: 'ctrl1', secondary_controllers: ['ctrl2', 'ctrl1'], ensure: 'present')
    end
  end

  describe 'update' do
    it 'puts to the zone path and omits the immutable type' do
      expect(transport).to receive(:call).with(
        context, 'PUT', '/cluster/sdn/zones/{zone}',
        body: { 'peers' => '10.1.0.1,10.1.0.2' },
        path_params: { 'zone' => 'zone1' }
      )

      provider.update(context, 'zone1', zone: 'zone1', type: 'vxlan', peers: '10.1.0.1,10.1.0.2', ensure: 'present')
    end

    it 'renders delete_properties as the comma-separated list PVE expects' do
      expect(transport).to receive(:call).with(
        context, 'PUT', '/cluster/sdn/zones/{zone}',
        body: { 'delete' => 'mtu,dnszone' },
        path_params: { 'zone' => 'zone1' }
      )

      provider.update(context, 'zone1', zone: 'zone1', type: 'simple', delete_properties: ['mtu', 'dnszone'], ensure: 'present')
    end
  end

  describe 'delete' do
    it 'deletes the zone path' do
      expect(transport).to receive(:call).with(context, 'DELETE', '/cluster/sdn/zones/{zone}', body: nil, path_params: { 'zone' => 'zone1' })
      provider.delete(context, 'zone1')
    end
  end

  describe 'plugin-conditional attributes' do
    it 'rejects an attribute PVE does not accept for the declared plugin type' do
      expect { provider.create(context, 'zone1', zone: 'zone1', type: 'simple', peers: '10.0.0.1', ensure: 'present') }
        .to raise_error(Puppet::ResourceError, %r{type 'simple' does not accept: peers \(vxlan, evpn only\)})
    end

    it 'names every misplaced attribute at once' do
      expect { provider.create(context, 'zone1', zone: 'zone1', type: 'vlan', bridge: 'vmbr0', vrf_vxlan: 10, service_vlan: 5, ensure: 'present') }
        .to raise_error(Puppet::ResourceError, %r{service_vlan \(qinq only\).*vrf_vxlan \(evpn only\)}m)
    end

    it 'allows an attribute that belongs to the declared plugin type' do
      allow(transport).to receive(:call)
      expect { provider.create(context, 'zone1', zone: 'zone1', type: 'qinq', bridge: 'vmbr0', service_vlan: 100, ensure: 'present') }
        .not_to raise_error
    end
  end

  describe 'the global SDN lock' do
    it 'turns a locked configuration into an actionable error' do
      allow(transport).to receive(:call).and_raise(
        Puppet::ResourceError, 'PVE API error 500 on /cluster/sdn/zones: invalid lock token provided!'
      )

      expect { provider.create(context, 'zone1', zone: 'zone1', type: 'simple', ensure: 'present') }
        .to raise_error(Puppet::ResourceError, %r{locked by another client.*pvesh delete /cluster/sdn/lock --force}m)
    end

    it 'leaves an unrelated API error untouched' do
      allow(transport).to receive(:call).and_raise(Puppet::ResourceError, 'PVE API error 400 on /cluster/sdn/zones: bad request')

      expect { provider.create(context, 'zone1', zone: 'zone1', type: 'simple', ensure: 'present') }
        .to raise_error(Puppet::ResourceError, %r{bad request})
    end
  end

  it 'never applies: no SDN provider but pve_sdn_apply may PUT /cluster/sdn' do
    allow(transport).to receive(:call)
    expect(transport).not_to receive(:call).with(context, 'PUT', '/cluster/sdn', any_args)

    provider.create(context, 'zone1', zone: 'zone1', type: 'simple', ensure: 'present')
    provider.update(context, 'zone1', zone: 'zone1', type: 'simple', mtu: 1500, ensure: 'present')
    provider.delete(context, 'zone1')
  end
end
