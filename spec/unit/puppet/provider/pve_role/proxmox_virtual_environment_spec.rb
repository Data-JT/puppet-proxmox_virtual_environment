# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_base_provider'
require 'puppet/provider/pve_role/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveRole::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:roleid]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
  end

  describe '#get' do
    it 'maps custom roles and converts the comma-separated privs string to an array' do
      allow(transport).to receive(:get).with(context, '/access/roles').and_return([
                                                                                    { 'roleid' => 'PackerBuild', 'privs' => 'VM.Audit,Datastore.AllocateSpace', 'special' => 0 },
                                                                                    { 'roleid' => 'PVEAuditor', 'privs' => 'Sys.Audit', 'special' => 1 },
                                                                                  ])
      result = provider.get(context)
      expect(result).to contain_exactly(
        hash_including(roleid: 'PackerBuild', privs: ['VM.Audit', 'Datastore.AllocateSpace'], ensure: 'present'),
      )
    end

    it 'excludes built-in (special) roles' do
      allow(transport).to receive(:get).with(context, '/access/roles').and_return([
                                                                                    { 'roleid' => 'Administrator', 'privs' => 'Sys.Audit', 'special' => 1 },
                                                                                  ])
      expect(provider.get(context)).to eq([])
    end

    it 'handles roles with no privileges' do
      allow(transport).to receive(:get).with(context, '/access/roles').and_return([
                                                                                    { 'roleid' => 'Empty', 'special' => 0 },
                                                                                  ])
      expect(provider.get(context)).to contain_exactly(hash_including(roleid: 'Empty', privs: []))
    end
  end

  describe '#create' do
    it 'posts the role ID and a comma-joined privs string' do
      should = { roleid: 'PackerBuild', privs: ['VM.Audit', 'Datastore.AllocateSpace'], ensure: 'present' }
      expect(transport).to receive(:post).with(
        context, '/access/roles',
        { 'roleid' => 'PackerBuild', 'privs' => 'VM.Audit,Datastore.AllocateSpace' }
      )
      provider.create(context, 'PackerBuild', should)
    end
  end

  describe '#update' do
    it 'puts a comma-joined privs string to /access/roles/{roleid}' do
      should = { roleid: 'PackerBuild', privs: ['VM.Audit'], ensure: 'present' }
      expect(transport).to receive(:put).with(context, '/access/roles/PackerBuild', { 'privs' => 'VM.Audit' })
      provider.update(context, 'PackerBuild', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /access/roles/{roleid}' do
      expect(transport).to receive(:delete).with(context, '/access/roles/PackerBuild')
      provider.delete(context, 'PackerBuild')
    end
  end

  describe '#insync?' do
    it 'treats reordered privilege lists as in sync, since PVE returns them in its own canonical order' do
      is = { privs: ['VM.Audit', 'Datastore.AllocateSpace', 'Sys.Audit'] }
      should = { privs: ['Sys.Audit', 'VM.Audit', 'Datastore.AllocateSpace'] }
      expect(provider.insync?(context, 'PackerBuild', :privs, is, should)).to be(true)
    end

    it 'reports a genuine difference in privilege membership as out of sync' do
      is = { privs: ['VM.Audit', 'Datastore.AllocateSpace'] }
      should = { privs: ['Sys.Audit', 'VM.Audit', 'Datastore.AllocateSpace'] }
      expect(provider.insync?(context, 'PackerBuild', :privs, is, should)).to be(false)
    end

    it 'delegates delete_properties comparison to the base implementation' do
      should = { delete_properties: ['privs'] }
      expect(provider.insync?(context, 'PackerBuild', :delete_properties, { privs: ['VM.Audit'] }, should)).to be(false)
      expect(provider.insync?(context, 'PackerBuild', :delete_properties, {}, should)).to be(true)
    end

    it 'returns nil for other attributes so the Resource API falls back to default comparison' do
      expect(provider.insync?(context, 'PackerBuild', :roleid, { roleid: 'a' }, { roleid: 'b' })).to be_nil
    end
  end
end
