# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_base_provider'
require 'puppet/provider/pve_group/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveGroup::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:groupid]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
  end

  describe '#get' do
    it 'maps groups and splits the users string into a members array' do
      allow(transport).to receive(:get).with(context, '/access/groups').and_return([
                                                                                     { 'groupid' => 'proxmox-admins', 'comment' => 'Admins', 'users' => 'alice@example,bob@example' },
                                                                                   ])
      expect(provider.get(context)).to contain_exactly(
        hash_including(
          groupid: 'proxmox-admins', comment: 'Admins',
          members: ['alice@example', 'bob@example'], ensure: 'present'
        ),
      )
    end

    it 'returns an empty members array for groups with no users' do
      allow(transport).to receive(:get).with(context, '/access/groups').and_return([
                                                                                     { 'groupid' => 'sales' },
                                                                                   ])
      expect(provider.get(context)).to contain_exactly(hash_including(groupid: 'sales', members: []))
    end
  end

  describe '#create' do
    it 'posts groupid and comment to /access/groups' do
      should = { groupid: 'sales', comment: 'Sales team', ensure: 'present' }
      expect(transport).to receive(:post).with(context, '/access/groups', hash_including('groupid' => 'sales', 'comment' => 'Sales team'))
      provider.create(context, 'sales', should)
    end
  end

  describe '#update' do
    it 'puts to /access/groups/{groupid} without the namevar' do
      should = { groupid: 'sales', comment: 'Updated', ensure: 'present' }
      expect(transport).to receive(:put) do |_ctx, path, body|
        expect(path).to eq('/access/groups/sales')
        expect(body).to include('comment' => 'Updated')
        expect(body).not_to have_key('groupid')
      end
      provider.update(context, 'sales', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /access/groups/{groupid}' do
      expect(transport).to receive(:delete).with(context, '/access/groups/sales')
      provider.delete(context, 'sales')
    end
  end
end
