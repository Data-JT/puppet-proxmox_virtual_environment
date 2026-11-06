# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_sdn_vnet'

RSpec.describe 'pve_sdn_vnet type' do
  let(:type) { Puppet::Type.type(:pve_sdn_vnet) }

  it 'is registered with vnet as the namevar' do
    expect(type.key_attributes).to eq([:vnet])
  end

  it 'declares the custom_insync feature so the provider insync? is consulted' do
    expect(type.type_definition.definition[:features]).to include('custom_insync')
  end

  it 'accepts a VNet with a VXLAN VNI' do
    resource = type.new(vnet: 'vnet1', zone: 'zone1', vnet_tag: 10_100, vlanaware: true)
    expect(resource[:zone]).to eq('zone1')
    expect(resource[:vnet_tag]).to eq(10_100)
    expect(resource[:vlanaware]).to eq(:true)
  end

  it 'accepts an alias and port isolation' do
    resource = type.new(vnet: 'vnet1', zone: 'zone1', vnet_alias: 'internal services', isolate_ports: true)
    expect(resource[:vnet_alias]).to eq('internal services')
    expect(resource[:isolate_ports]).to eq(:true)
  end

  # Puppet reserves both 'tag' and 'alias' as metaparameters, so the PVE names
  # cannot be used verbatim.
  it 'renames the reserved PVE attribute names' do
    attributes = type.type_definition.attributes
    expect(attributes).to include(:vnet_tag, :vnet_alias)
    expect(attributes).not_to include(:tag, :alias)
  end

  it 'treats type as immutable' do
    expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
  end

  it 'keeps zone settable, because PVE allows moving a VNet between zones' do
    expect(type.type_definition.attributes[:zone][:behaviour]).to be_nil
  end

  it 'rejects a VNet identifier longer than the 8 characters PVE allows' do
    expect { type.new(vnet: 'thisiswaytoolong', zone: 'zone1') }.to raise_error(Puppet::ResourceError)
  end

  it 'exposes pending_state as read-only' do
    expect(type.type_definition.attributes[:pending_state][:behaviour]).to eq(:read_only)
  end
end
