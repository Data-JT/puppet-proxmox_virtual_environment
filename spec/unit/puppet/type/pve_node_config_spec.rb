# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_node_config'

RSpec.describe 'pve_node_config type' do
  let(:type) { Puppet::Type.type(:pve_node_config) }

  it 'is registered with node as the namevar' do
    expect(type.key_attributes).to eq([:node])
  end

  it 'accepts PVE node configuration fields' do
    resource = type.new(
      node: 'pve01',
      description: 'Managed by Puppet',
      location: 'room=dc1,rack=a1',
      wakeonlan: 'mac=AA:BB:CC:DD:EE:FF,bind-interface=vmbr0',
      startall_onboot_delay: 30,
      ballooning_target: 80,
    )
    expect(resource[:description]).to eq('Managed by Puppet')
    expect(resource[:startall_onboot_delay]).to eq(30)
    expect(resource[:ballooning_target]).to eq(80)
  end

  it 'rejects a ballooning target above 100 percent' do
    expect { type.new(node: 'pve01', ballooning_target: 101) }.to raise_error(Puppet::ResourceError)
  end
end
