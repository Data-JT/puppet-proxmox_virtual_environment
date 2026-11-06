# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_sdn_ipam/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveSdnIpam::ProxmoxVirtualEnvironment do
  let(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:immutable_attributes) { { type: { behaviour: :init_only } } }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:ipam], attributes: immutable_attributes) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
    allow(transport).to receive(:get).with(context, '/cluster/sdn/ipams').and_return(
      [{ 'ipam' => 'netbox1', 'type' => 'netbox', 'url' => 'https://netbox.example.com/api', 'token' => 'stored-token' }],
    )
  end

  it 'issues no pending read, because IPAM changes take effect immediately' do
    expect(transport).not_to receive(:get).with(context, '/cluster/sdn/ipams', anything)
    provider.get(context)
  end

  it 'reads the token back from the API, so it can be compared' do
    expect(provider.get(context).first[:token]).to eq('stored-token')
  end

  it 'reports drift when the declared token differs from the stored one' do
    expect(provider.insync?(context, 'netbox1', :token, { token: 'stored-token' }, token: 'rotated')).to be_nil
  end

  it 'posts a create body' do
    expect(transport).to receive(:call).with(
      context, 'POST', '/cluster/sdn/ipams',
      body: { 'ipam' => 'phpipam1', 'type' => 'phpipam', 'url' => 'https://ipam.example.com/api', 'token' => 'secret-token', 'section' => 3 },
      path_params: {}
    )

    provider.create(context, 'phpipam1', ipam: 'phpipam1', type: 'phpipam', url: 'https://ipam.example.com/api', token: 'secret-token', section: 3, ensure: 'present')
  end

  it 'deletes the IPAM path' do
    expect(transport).to receive(:call).with(context, 'DELETE', '/cluster/sdn/ipams/{ipam}', body: nil, path_params: { 'ipam' => 'netbox1' })
    provider.delete(context, 'netbox1')
  end
end
