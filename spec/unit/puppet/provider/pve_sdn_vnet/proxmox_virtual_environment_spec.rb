# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_sdn_vnet/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveSdnVnet::ProxmoxVirtualEnvironment do
  let(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:immutable_attributes) { { type: { behaviour: :init_only } } }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:vnet], attributes: immutable_attributes) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
    allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets', { 'pending' => 1 }).and_return([])
  end

  it 'maps the reserved PVE names onto the renamed attributes' do
    allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets')
                                     .and_return([{ 'vnet' => 'vnet1', 'zone' => 'zone1', 'tag' => 10_100, 'alias' => 'internal', 'vlanaware' => 1 }])

    expect(provider.get(context).first).to include(vnet: 'vnet1', zone: 'zone1', vnet_tag: 10_100, vnet_alias: 'internal', vlanaware: true)
  end

  it 'reports a VNet awaiting apply' do
    allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets').and_return([{ 'vnet' => 'vnet1', 'zone' => 'zone1' }])
    allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets', { 'pending' => 1 })
                                     .and_return([{ 'vnet' => 'vnet1', 'state' => 'new', 'pending' => {} }])

    expect(provider.get(context).first[:pending_state]).to eq('new')
  end

  it 'posts a create body using PVE attribute names' do
    expect(transport).to receive(:call).with(
      context, 'POST', '/cluster/sdn/vnets',
      body: { 'vnet' => 'vnet1', 'zone' => 'zone1', 'tag' => 10_100, 'vlanaware' => true },
      path_params: {}
    )

    provider.create(context, 'vnet1', vnet: 'vnet1', zone: 'zone1', vnet_tag: 10_100, vlanaware: true, ensure: 'present')
  end

  it 'puts an update to the VNet path without the namevar' do
    expect(transport).to receive(:call).with(
      context, 'PUT', '/cluster/sdn/vnets/{vnet}',
      body: { 'zone' => 'zone2' },
      path_params: { 'vnet' => 'vnet1' }
    )

    provider.update(context, 'vnet1', vnet: 'vnet1', zone: 'zone2', ensure: 'present')
  end

  it 'deletes the VNet path' do
    expect(transport).to receive(:call).with(context, 'DELETE', '/cluster/sdn/vnets/{vnet}', body: nil, path_params: { 'vnet' => 'vnet1' })
    provider.delete(context, 'vnet1')
  end

  it 'never applies' do
    allow(transport).to receive(:call)
    expect(transport).not_to receive(:call).with(context, 'PUT', '/cluster/sdn', any_args)
    provider.update(context, 'vnet1', vnet: 'vnet1', zone: 'zone2', ensure: 'present')
  end
end
