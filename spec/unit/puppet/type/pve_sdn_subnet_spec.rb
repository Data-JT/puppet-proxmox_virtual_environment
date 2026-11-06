# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_sdn_subnet'

RSpec.describe 'pve_sdn_subnet type' do
  let(:type) { Puppet::Type.type(:pve_sdn_subnet) }

  it 'is keyed by the VNet and the CIDR together' do
    expect(type.key_attributes).to eq([:vnet, :cidr])
  end

  it 'declares the custom_insync feature so the provider insync? is consulted' do
    expect(type.type_definition.definition[:features]).to include('custom_insync')
  end

  describe 'title parsing' do
    it 'splits a pipe-separated title into VNet and CIDR' do
      resource = type.new(title: 'vnet1|10.0.0.0/24')
      expect(resource[:vnet]).to eq('vnet1')
      expect(resource[:cidr]).to eq('10.0.0.0/24')
    end

    it 'keeps the slash inside the CIDR rather than splitting on it' do
      expect(type.new(title: 'vnet1|10.0.0.0/24')[:cidr]).to eq('10.0.0.0/24')
    end

    it 'handles an IPv6 CIDR' do
      resource = type.new(title: 'vnet1|2001:db8::/64')
      expect(resource[:vnet]).to eq('vnet1')
      expect(resource[:cidr]).to eq('2001:db8::/64')
    end

    it 'accepts explicit parameters with a bare title' do
      resource = type.new(title: 'vnet1', cidr: '10.0.0.0/24')
      expect(resource[:vnet]).to eq('vnet1')
      expect(resource[:cidr]).to eq('10.0.0.0/24')
    end
  end

  it 'accepts gateway, SNAT and DHCP settings' do
    resource = type.new(
      title:           'vnet1|10.0.0.0/24',
      gateway:         '10.0.0.1',
      snat:            true,
      dhcp_range:      ['start-address=10.0.0.100,end-address=10.0.0.200'],
      dhcp_dns_server: '10.0.0.1',
    )
    expect(resource[:gateway]).to eq('10.0.0.1')
    expect(resource[:snat]).to eq(:true)
    expect(resource[:dhcp_range]).to eq(['start-address=10.0.0.100,end-address=10.0.0.200'])
  end

  it 'exposes the derived PVE identifier as read-only' do
    expect(type.type_definition.attributes[:subnet_id][:behaviour]).to eq(:read_only)
  end

  it 'exposes pending_state as read-only' do
    expect(type.type_definition.attributes[:pending_state][:behaviour]).to eq(:read_only)
  end

  it 'treats type as immutable' do
    expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
  end
end
