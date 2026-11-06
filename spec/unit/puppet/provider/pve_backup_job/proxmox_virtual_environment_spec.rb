# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_backup_job/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveBackupJob::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:id]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
  end

  it 'reads scheduled vzdump jobs' do
    allow(transport).to receive(:get).with(context, '/cluster/backup').and_return([
                                                                                    { 'id' => 'nightly', 'enabled' => 1, 'schedule' => 'daily', 'storage' => 'backup', 'all' => 1 },
                                                                                  ])
    expect(provider.get(context)).to contain_exactly(
      hash_including(id: 'nightly', enabled: true, job_schedule: 'daily', storage: 'backup', all: true, ensure: 'present'),
    )
  end

  it 'creates a scheduled vzdump job' do
    should = { id: 'nightly', job_schedule: 'daily', storage: 'backup', all: true, ensure: 'present' }
    expect(transport).to receive(:post).with(context, '/cluster/backup', hash_including('id' => 'nightly', 'all' => true))
    provider.create(context, 'nightly', should)
  end

  it 'updates and deletes a scheduled vzdump job' do
    should = { id: 'nightly', job_schedule: 'weekly', enabled: false, ensure: 'present' }
    expect(transport).to receive(:put).with(context, '/cluster/backup/nightly', { 'enabled' => false, 'schedule' => 'weekly' })
    provider.update(context, 'nightly', should)
    expect(transport).to receive(:delete).with(context, '/cluster/backup/nightly')
    provider.delete(context, 'nightly')
  end

  describe '#insync?' do
    it 'treats vmid as in sync when the declared array matches the PVE list regardless of order' do
      should = { vmid: [200, 100] }
      expect(provider.insync?(context, 'nightly', :vmid, { vmid: '100,200' }, should)).to be(true)
    end

    it 'treats vmid as out of sync when the declared array differs from the PVE list' do
      should = { vmid: [100, 300] }
      expect(provider.insync?(context, 'nightly', :vmid, { vmid: '100,200' }, should)).to be(false)
    end

    it 'treats exclude as an unordered set as well' do
      should = { exclude: [102, 101] }
      expect(provider.insync?(context, 'nightly', :exclude, { exclude: '101,102' }, should)).to be(true)
    end

    it 'falls back to the base comparison for other attributes' do
      should = { job_schedule: 'daily' }
      expect(provider.insync?(context, 'nightly', :job_schedule, { job_schedule: 'daily' }, should)).to be_nil
    end
  end

  it 'joins vmid and exclude arrays into comma-separated lists for create and update requests' do
    should = {
      id: 'nightly', vmid: [100, 200], exclude: [101, 102], ensure: 'present',
    }
    expect(transport).to receive(:post).with(
      context,
      '/cluster/backup',
      hash_including('vmid' => '100,200', 'exclude' => '101,102'),
    )
    provider.create(context, 'nightly', should)

    expect(transport).to receive(:put).with(
      context,
      '/cluster/backup/nightly',
      hash_including('vmid' => '100,200', 'exclude' => '101,102'),
    )
    provider.update(context, 'nightly', should)
  end

  it 'maps fleecing and performance when reading' do
    allow(transport).to receive(:get).with(context, '/cluster/backup').and_return([
                                                                                    { 'id' => 'nightly', 'fleecing' => 'enabled=1,storage=local-lvm', 'performance' => 'max-workers=2' },
                                                                                  ])
    expect(provider.get(context)).to contain_exactly(
      hash_including(id: 'nightly', fleecing: 'enabled=1,storage=local-lvm', performance: 'max-workers=2'),
    )
  end

  it 're-encodes fleecing and prune_backups as property strings when PVE returns them as nested objects' do
    allow(transport).to receive(:get).with(context, '/cluster/backup').and_return([
                                                                                    { 'id' => 'nightly', 'fleecing' => { 'enabled' => 0 }, 'prune-backups' => { 'keep-last' => '7' } },
                                                                                  ])
    expect(provider.get(context)).to contain_exactly(
      hash_including(id: 'nightly', fleecing: 'enabled=0', prune_backups: 'keep-last=7'),
    )
  end

  it 'sends fleecing and performance on create and update' do
    should = {
      id: 'nightly', job_schedule: 'daily', fleecing: 'enabled=1,storage=local-lvm',
      performance: 'max-workers=2,pbs-entries-max=1024', ensure: 'present',
    }
    expect(transport).to receive(:post).with(
      context,
      '/cluster/backup',
      hash_including('fleecing' => 'enabled=1,storage=local-lvm', 'performance' => 'max-workers=2,pbs-entries-max=1024'),
    )
    provider.create(context, 'nightly', should)

    expect(transport).to receive(:put).with(
      context,
      '/cluster/backup/nightly',
      hash_including('fleecing' => 'enabled=1,storage=local-lvm', 'performance' => 'max-workers=2,pbs-entries-max=1024'),
    )
    provider.update(context, 'nightly', should)
  end
end
