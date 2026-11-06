# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_base_provider'
require 'puppet/provider/pve_pool/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PvePool::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:poolid]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
  end

  describe '#get' do
    it 'maps the API response to Puppet resource hashes' do
      allow(transport).to receive(:get).with(context, '/pools').and_return([
                                                                             { 'poolid' => 'Customers', 'comment' => 'Customer VMs' },
                                                                           ])
      expect(provider.get(context)).to contain_exactly(
        hash_including(poolid: 'Customers', comment: 'Customer VMs', ensure: 'present'),
      )
    end

    it 'returns [] when the API returns nil' do
      allow(transport).to receive(:get).with(context, '/pools').and_return(nil)
      expect(provider.get(context)).to eq([])
    end
  end

  describe '#create' do
    it 'posts to /pools' do
      should = { poolid: 'Customers', comment: 'Customer VMs', ensure: 'present' }
      expect(transport).to receive(:post).with(context, '/pools', hash_including('poolid' => 'Customers', 'comment' => 'Customer VMs'))
      provider.create(context, 'Customers', should)
    end
  end

  describe '#update' do
    it 'puts to /pools/{poolid} without the namevar' do
      should = { poolid: 'Customers', comment: 'Updated', ensure: 'present' }
      expect(transport).to receive(:put) do |_ctx, path, body|
        expect(path).to eq('/pools/Customers')
        expect(body).to include('comment' => 'Updated')
        expect(body).not_to have_key('poolid')
      end
      provider.update(context, 'Customers', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /pools/{poolid}' do
      expect(transport).to receive(:delete).with(context, '/pools/Customers')
      provider.delete(context, 'Customers')
    end
  end
end
