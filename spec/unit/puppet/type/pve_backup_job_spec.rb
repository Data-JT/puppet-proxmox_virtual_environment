# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_backup_job'

RSpec.describe 'pve_backup_job type' do
  let(:type) { Puppet::Type.type(:pve_backup_job) }

  it 'is registered with id as the namevar' do
    expect(type.key_attributes).to eq([:id])
  end

  it 'accepts a scheduled vzdump job' do
    resource = type.new(
      id: 'nightly',
      enabled: true,
      job_schedule: 'daily',
      storage: 'backup',
      mode: 'snapshot',
      all: true,
      prune_backups: 'keep-daily=7,keep-weekly=4',
    )
    expect(resource[:job_schedule]).to eq('daily')
    expect(resource[:mode]).to eq('snapshot')
    expect(resource[:all]).to eq(:true)
  end

  it 'accepts fleecing and performance property strings' do
    resource = type.new(
      id: 'nightly',
      fleecing: 'enabled=1,storage=local-lvm',
      performance: 'max-workers=2,pbs-entries-max=1024',
    )
    expect(resource[:fleecing]).to eq('enabled=1,storage=local-lvm')
    expect(resource[:performance]).to eq('max-workers=2,pbs-entries-max=1024')
  end
end
