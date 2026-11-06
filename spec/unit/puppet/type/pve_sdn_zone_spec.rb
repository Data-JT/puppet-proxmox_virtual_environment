# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_sdn_zone'

RSpec.describe 'pve_sdn_zone type' do
  let(:type) { Puppet::Type.type(:pve_sdn_zone) }

  it 'is registered with zone as the namevar' do
    expect(type.key_attributes).to eq([:zone])
  end

  it 'declares the custom_insync feature so the provider insync? is consulted' do
    expect(type.type_definition.definition[:features]).to include('custom_insync')
  end

  it 'treats type as immutable' do
    expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
  end

  it 'accepts a simple zone' do
    resource = type.new(zone: 'zone1', type: 'simple', ipam: 'pve')
    expect(resource[:type]).to eq('simple')
    expect(resource[:ipam]).to eq('pve')
  end

  it 'accepts a vxlan zone with peers' do
    resource = type.new(zone: 'zone1', type: 'vxlan', peers: '10.0.0.1,10.0.0.2', mtu: 1450)
    expect(resource[:peers]).to eq('10.0.0.1,10.0.0.2')
    expect(resource[:mtu]).to eq(1450)
  end

  it 'accepts an evpn zone with controller and exit nodes' do
    resource = type.new(
      zone:                  'zone1',
      type:                  'evpn',
      controller:            'ctrl1',
      secondary_controllers: ['ctrl2'],
      vrf_vxlan:             10_000,
      exitnodes:             'node1,node2',
      advertise_subnets:     true,
    )
    expect(resource[:vrf_vxlan]).to eq(10_000)
    expect(resource[:secondary_controllers]).to eq(['ctrl2'])
    expect(resource[:advertise_subnets]).to eq(:true)
  end

  it 'accepts a qinq zone with a service VLAN' do
    resource = type.new(zone: 'zone1', type: 'qinq', bridge: 'vmbr0', service_vlan: 100, vlan_protocol: '802.1ad')
    expect(resource[:service_vlan]).to eq(100)
    expect(resource[:vlan_protocol]).to eq('802.1ad')
  end

  it 'rejects an unknown plugin type' do
    expect { type.new(zone: 'zone1', type: 'bogus') }.to raise_error(Puppet::ResourceError)
  end

  it 'rejects a zone identifier longer than the 8 characters PVE allows' do
    expect { type.new(zone: 'thisiswaytoolong', type: 'simple') }.to raise_error(Puppet::ResourceError)
  end

  # PVE's own attribute is called 'tag', which Puppet reserves as a
  # metaparameter, so the type cannot expose that name.
  it 'exposes the qinq service VLAN as service_vlan rather than tag' do
    expect(type.type_definition.attributes).to have_key(:service_vlan)
    expect(type.type_definition.attributes).not_to have_key(:tag)
  end

  describe 'pending_state' do
    it 'is read-only, so an unapplied change is reported but never enforced' do
      expect(type.type_definition.attributes[:pending_state][:behaviour]).to eq(:read_only)
    end

    it 'cannot be set from a manifest' do
      expect { type.new(zone: 'zone1', type: 'simple', pending_state: 'changed') }
        .to raise_error(Puppet::ResourceError, %r{read_only})
    end
  end
end
