# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_sdn_controller/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveSdnController::ProxmoxVirtualEnvironment do
  let(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:immutable_attributes) { { type: { behaviour: :init_only } } }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:controller], attributes: immutable_attributes) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
    allow(transport).to receive(:get).with(context, '/cluster/sdn/controllers', { 'pending' => 1 }).and_return([])
  end

  it 'maps the hyphenated PVE names onto underscored attributes' do
    allow(transport).to receive(:get).with(context, '/cluster/sdn/controllers').and_return(
      [{ 'controller' => 'ctrl1', 'type' => 'evpn', 'asn' => 65_000, 'peer-group-name' => 'VTEP', 'bgp-multipath-as-path-relax' => 1 }],
    )

    expect(provider.get(context).first).to include(controller: 'ctrl1', asn: 65_000, peer_group_name: 'VTEP', bgp_multipath_as_path_relax: true)
  end

  it 'posts an EVPN controller' do
    expect(transport).to receive(:call).with(
      context, 'POST', '/cluster/sdn/controllers',
      body: { 'controller' => 'ctrl1', 'type' => 'evpn', 'asn' => 65_000, 'peers' => '10.0.0.1,10.0.0.2' },
      path_params: {}
    )

    provider.create(context, 'ctrl1', controller: 'ctrl1', type: 'evpn', asn: 65_000, peers: '10.0.0.1,10.0.0.2', ensure: 'present')
  end

  it 'puts an update without the immutable type' do
    expect(transport).to receive(:call).with(
      context, 'PUT', '/cluster/sdn/controllers/{controller}',
      body: { 'asn' => 65_001 },
      path_params: { 'controller' => 'ctrl1' }
    )

    provider.update(context, 'ctrl1', controller: 'ctrl1', type: 'evpn', asn: 65_001, ensure: 'present')
  end

  it 'deletes the controller path' do
    expect(transport).to receive(:call).with(context, 'DELETE', '/cluster/sdn/controllers/{controller}', body: nil, path_params: { 'controller' => 'ctrl1' })
    provider.delete(context, 'ctrl1')
  end

  it 'treats reordered peers as in sync' do
    expect(provider.insync?(context, 'ctrl1', :peers, { peers: '10.0.0.2,10.0.0.1' }, peers: '10.0.0.1,10.0.0.2')).to be(true)
  end

  it 'treats reordered IS-IS interfaces as in sync' do
    expect(provider.insync?(context, 'ctrl1', :isis_ifaces, { isis_ifaces: 'eth1,eth0' }, isis_ifaces: 'eth0,eth1')).to be(true)
  end

  it 'reports an unapplied controller' do
    allow(transport).to receive(:get).with(context, '/cluster/sdn/controllers').and_return([{ 'controller' => 'ctrl1', 'type' => 'evpn' }])
    allow(transport).to receive(:get).with(context, '/cluster/sdn/controllers', { 'pending' => 1 })
                                     .and_return([{ 'controller' => 'ctrl1', 'state' => 'changed', 'pending' => { 'asn' => 65_001 } }])

    expect(provider.get(context).first[:pending_state]).to eq('changed')
  end
end
