# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_node_config/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveNodeConfig::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:node]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
  end

  it 'reads configuration for every PVE node' do
    allow(transport).to receive(:get).with(context, '/nodes').and_return([
                                                                           { 'node' => 'pve01' },
                                                                           { 'node' => 'pve02' },
                                                                         ])
    allow(transport).to receive(:get).with(context, '/nodes/pve01/config').and_return(
      'description' => "Managed\n", 'startall-onboot-delay' => 30,
    )
    allow(transport).to receive(:get).with(context, '/nodes/pve02/config').and_return(
      'description' => 'Second node',
    )
    expect(provider.get(context)).to contain_exactly(
      hash_including(node: 'pve01', description: 'Managed', startall_onboot_delay: 30, ensure: 'present'),
      hash_including(node: 'pve02', description: 'Second node', ensure: 'present'),
    )
  end

  it 'skips a node whose config lookup fails and continues with the remaining nodes' do
    allow(transport).to receive(:get).with(context, '/nodes').and_return([
                                                                           { 'node' => 'pve01' },
                                                                           { 'node' => 'pve02' },
                                                                         ])
    allow(transport).to receive(:get).with(context, '/nodes/pve01/config')
                                     .and_raise(Puppet::ResourceError, 'connection refused')
    allow(transport).to receive(:get).with(context, '/nodes/pve02/config')
                                     .and_return('description' => 'Second node')
    allow(context).to receive(:warning)

    expect(context).to receive(:warning).with(%r{Skipping PVE node 'pve01': connection refused})
    result = provider.get(context)
    expect(result).to contain_exactly(hash_including(node: 'pve02', description: 'Second node', ensure: 'present'))
  end

  it 'updates PVE node fields' do
    should = { node: 'pve01', description: 'Managed', wakeonlan: 'AA:BB:CC:DD:EE:FF', ensure: 'present' }
    expect(transport).to receive(:put).with(
      context,
      '/nodes/pve01/config',
      { 'description' => 'Managed', 'wakeonlan' => 'AA:BB:CC:DD:EE:FF' },
    )
    provider.update(context, 'pve01', should)
  end

  it 'rejects ensure absent because PVE node config cannot be deleted' do
    expect { provider.delete(context, 'pve01') }
      .to raise_error(Puppet::ResourceError, %r{cannot be deleted})
  end
end
