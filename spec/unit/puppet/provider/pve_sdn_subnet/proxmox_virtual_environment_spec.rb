# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_sdn_subnet/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveSdnSubnet::ProxmoxVirtualEnvironment do
  let(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:immutable_attributes) { { type: { behaviour: :init_only } } }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:vnet, :cidr], attributes: immutable_attributes) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }
  let(:name) { { vnet: 'vnet1', cidr: '10.0.0.0/24' } }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
    allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets').and_return([{ 'vnet' => 'vnet1', 'zone' => 'zone1' }])
    allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets/vnet1/subnets', { 'pending' => 1 }).and_return([])
  end

  describe 'identity' do
    before(:each) do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets/vnet1/subnets')
                                       .and_return([{ 'subnet' => 'zone1-10.0.0.0-24', 'vnet' => 'vnet1', 'type' => 'subnet', 'gateway' => '10.0.0.1' }])
    end

    # PVE derives the identifier as <zone>-<address>-<prefix>; the CIDR is what
    # a user declares, so discovery has to invert that mapping.
    it 'recovers the CIDR from the identifier PVE derived' do
      result = provider.get(context).first
      expect(result).to include(vnet: 'vnet1', cidr: '10.0.0.0/24', subnet_id: 'zone1-10.0.0.0-24')
    end

    it 'walks every VNet, because subnets are only reachable nested under one' do
      expect(transport).to receive(:get).with(context, '/cluster/sdn/vnets').and_return([{ 'vnet' => 'vnet1', 'zone' => 'zone1' }])
      expect(transport).to receive(:get).with(context, '/cluster/sdn/vnets/vnet1/subnets').and_return([])
      provider.get(context)
    end

    it 'addresses updates by the derived identifier, not the CIDR' do
      provider.get(context)

      expect(transport).to receive(:call).with(
        context, 'PUT', '/cluster/sdn/vnets/{vnet}/subnets/{subnet}',
        body: { 'gateway' => '10.0.0.254' },
        path_params: { vnet: 'vnet1', subnet: 'zone1-10.0.0.0-24' }
      )

      provider.update(context, name, vnet: 'vnet1', cidr: '10.0.0.0/24', gateway: '10.0.0.254', ensure: 'present')
    end

    it 'addresses deletes by the derived identifier' do
      provider.get(context)

      expect(transport).to receive(:call).with(
        context, 'DELETE', '/cluster/sdn/vnets/{vnet}/subnets/{subnet}',
        body: nil, path_params: { vnet: 'vnet1', subnet: 'zone1-10.0.0.0-24' }
      )

      provider.delete(context, name)
    end

    # Without a prior discovery there is no cached identifier, so the provider
    # has to resolve the VNet's zone and derive it the same way PVE does.
    it 'derives the identifier from the VNet zone when discovery did not run' do
      expect(transport).to receive(:call).with(context, 'GET', '/cluster/sdn/vnets/{vnet}', path_params: { vnet: 'vnet1' })
                                         .and_return({ 'vnet' => 'vnet1', 'zone' => 'zone1' })
      expect(transport).to receive(:call).with(
        context, 'DELETE', '/cluster/sdn/vnets/{vnet}/subnets/{subnet}',
        body: nil, path_params: { vnet: 'vnet1', subnet: 'zone1-10.0.0.0-24' }
      )

      provider.delete(context, name)
    end

    it 'raises a clear error when the VNet zone cannot be resolved' do
      allow(transport).to receive(:call).with(context, 'GET', '/cluster/sdn/vnets/{vnet}', path_params: { vnet: 'vnet1' }).and_return(nil)

      expect { provider.delete(context, name) }
        .to raise_error(Puppet::ResourceError, %r{Cannot determine the zone of SDN VNet 'vnet1'})
    end
  end

  describe 'create' do
    before(:each) do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets/vnet1/subnets').and_return([])
    end

    # Only the create endpoint accepts a bare CIDR; PVE derives the identifier
    # from it, so no zone lookup is needed here.
    it 'posts the CIDR and forces the object type PVE requires' do
      expect(transport).to receive(:call).with(
        context, 'POST', '/cluster/sdn/vnets/{vnet}/subnets',
        body: { 'vnet' => 'vnet1', 'subnet' => '10.0.0.0/24', 'type' => 'subnet', 'gateway' => '10.0.0.1', 'snat' => true },
        path_params: { vnet: 'vnet1' }
      )

      provider.create(context, name, vnet: 'vnet1', cidr: '10.0.0.0/24', gateway: '10.0.0.1', snat: true, ensure: 'present')
    end
  end

  describe 'dhcp_range' do
    # PVE accepts property strings but hands back expanded objects, in its own
    # key order, so both levels are normalised before comparison.
    it 'serialises the objects PVE returns back into property strings' do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets/vnet1/subnets').and_return(
        [{ 'subnet' => 'zone1-10.0.0.0-24', 'vnet' => 'vnet1',
           'dhcp-range' => [{ 'start-address' => '10.0.0.100', 'end-address' => '10.0.0.200' }] }],
      )

      expect(provider.get(context).first[:dhcp_range]).to eq(['end-address=10.0.0.200,start-address=10.0.0.100'])
    end

    it 'is in sync regardless of key order inside each range' do
      is = { dhcp_range: ['end-address=10.0.0.200,start-address=10.0.0.100'] }
      should = { dhcp_range: ['start-address=10.0.0.100,end-address=10.0.0.200'] }
      expect(provider.insync?(context, name, :dhcp_range, is, should)).to be(true)
    end

    it 'is in sync regardless of the order of the ranges themselves' do
      is = { dhcp_range: ['start-address=10.0.0.100,end-address=10.0.0.150', 'start-address=10.0.0.200,end-address=10.0.0.250'] }
      should = { dhcp_range: ['start-address=10.0.0.200,end-address=10.0.0.250', 'start-address=10.0.0.100,end-address=10.0.0.150'] }
      expect(provider.insync?(context, name, :dhcp_range, is, should)).to be(true)
    end

    it 'reports a genuinely changed range as out of sync' do
      is = { dhcp_range: ['start-address=10.0.0.100,end-address=10.0.0.150'] }
      should = { dhcp_range: ['start-address=10.0.0.100,end-address=10.0.0.199'] }
      expect(provider.insync?(context, name, :dhcp_range, is, should)).to be(false)
    end
  end

  describe 'pending state' do
    it 'reports a subnet awaiting apply' do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets/vnet1/subnets')
                                       .and_return([{ 'subnet' => 'zone1-10.0.0.0-24', 'vnet' => 'vnet1' }])
      allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets/vnet1/subnets', { 'pending' => 1 })
                                       .and_return([{ 'subnet' => 'zone1-10.0.0.0-24', 'state' => 'new', 'pending' => {} }])

      expect(provider.get(context).first[:pending_state]).to eq('new')
    end
  end
end
