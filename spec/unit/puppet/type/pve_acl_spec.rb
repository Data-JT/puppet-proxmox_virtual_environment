# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_acl'

RSpec.describe 'pve_acl type' do
  let(:type) { Puppet::Type.type(:pve_acl) }

  # Helper: build a resource using the pipe-separated title pattern.
  def new_acl(path: '/', ugid: 'admin@pve', role: 'Admin', **attrs)
    type.new(title: "#{path}|#{ugid}|#{role}", **attrs)
  end

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has acl_path, ugid, and role as namevars' do
    expect(type.key_attributes).to include(:acl_path, :ugid, :role)
  end

  describe 'title_patterns' do
    it 'parses a pipe-separated title into all three namevars' do
      resource = type.new(title: '/storage/local|backup@pve|StorageBackup')
      expect(resource[:acl_path]).to eq('/storage/local')
      expect(resource[:ugid]).to eq('backup@pve')
      expect(resource[:role]).to eq('StorageBackup')
    end

    it 'treats a plain title as acl_path, with ugid and role supplied separately' do
      resource = type.new(title: '/storage', ugid: 'user@pve', role: 'StorageAudit')
      expect(resource[:acl_path]).to eq('/storage')
      expect(resource[:ugid]).to eq('user@pve')
      expect(resource[:role]).to eq('StorageAudit')
    end

    it 'rejects an empty title' do
      expect { type.new(title: '', ugid: 'user@pve', role: 'StorageAudit') }.to raise_error(Puppet::Error, %r{No set of title patterns matched})
    end
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = new_acl(ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = new_acl(ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'role attribute' do
    ['Admin', 'Audit', 'StorageAdmin', 'StorageBackup', 'StorageAudit', 'StorageReader',
     'RemoteAdmin', 'RemoteAudit', 'TapeAdmin', 'TapeAudit', 'TapeOperator', 'TapeReader'].each do |role|
      it "accepts #{role}" do
        expect { new_acl(role: role) }.not_to raise_error
      end
    end

    it 'accepts custom PVE roles' do
      expect { new_acl(role: 'AutomationOperator') }.not_to raise_error
    end
  end

  describe 'propagate attribute' do
    it 'defaults to true' do
      resource = new_acl
      expect(resource[:propagate]).to eq(:true)
    end

    it 'accepts false' do
      resource = new_acl(propagate: false)
      expect(resource[:propagate]).to eq(:false)
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) { type.new(title: '/storage/local|backup@pve|StorageBackup', propagate: false) }

    it { expect(resource[:acl_path]).to eq('/storage/local') }
    it { expect(resource[:ugid]).to eq('backup@pve') }
    it { expect(resource[:role]).to eq('StorageBackup') }
    it { expect(resource[:propagate]).to eq(:false) }
  end
end
