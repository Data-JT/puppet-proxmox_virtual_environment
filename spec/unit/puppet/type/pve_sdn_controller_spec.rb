# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_sdn_controller'

RSpec.describe 'pve_sdn_controller type' do
  let(:type) { Puppet::Type.type(:pve_sdn_controller) }

  it 'is registered with controller as the namevar' do
    expect(type.key_attributes).to eq([:controller])
  end

  it 'declares the custom_insync feature so the provider insync? is consulted' do
    expect(type.type_definition.definition[:features]).to include('custom_insync')
  end

  it 'treats type as immutable' do
    expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
  end

  it 'accepts an EVPN controller' do
    resource = type.new(controller: 'ctrl1', type: 'evpn', asn: 65_000, peers: '10.0.0.1,10.0.0.2')
    expect(resource[:asn]).to eq(65_000)
    expect(resource[:peers]).to eq('10.0.0.1,10.0.0.2')
  end

  it 'accepts a BGP controller bound to a node' do
    resource = type.new(controller: 'ctrl1', type: 'bgp', node: 'node1', asn: 65_000, ebgp: true, ebgp_multihop: 2, loopback: 'dummy1')
    expect(resource[:node]).to eq('node1')
    expect(resource[:ebgp]).to eq(:true)
    expect(resource[:ebgp_multihop]).to eq(2)
  end

  it 'accepts an IS-IS controller' do
    resource = type.new(controller: 'ctrl1', type: 'isis', isis_domain: 'domain1', isis_ifaces: 'eth0,eth1', isis_net: '49.0001.1111.1111.1111.00')
    expect(resource[:isis_domain]).to eq('domain1')
    expect(resource[:isis_ifaces]).to eq('eth0,eth1')
  end

  it 'rejects an unknown plugin type' do
    expect { type.new(controller: 'ctrl1', type: 'bogus') }.to raise_error(Puppet::ResourceError)
  end

  it 'exposes pending_state as read-only' do
    expect(type.type_definition.attributes[:pending_state][:behaviour]).to eq(:read_only)
  end
end
