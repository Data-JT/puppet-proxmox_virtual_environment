# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_storage'

RSpec.describe 'pve_storage type' do
  let(:type) { Puppet::Type.type(:pve_storage) }

  it 'is registered with storage as the namevar' do
    expect(type.key_attributes).to eq([:storage])
  end

  it 'declares the custom_insync feature so the provider insync? is consulted' do
    expect(type.type_definition.definition[:features]).to include('custom_insync')
  end

  it 'accepts a directory storage' do
    resource = type.new(storage: 'local-backup', type: 'dir', path: '/srv/backups', content: 'backup')
    expect(resource[:storage]).to eq('local-backup')
    expect(resource[:type]).to eq('dir')
    expect(resource[:path]).to eq('/srv/backups')
  end

  it 'accepts an NFS storage' do
    resource = type.new(
      storage: 'nfs-backup',
      type: 'nfs',
      server: 'nfs.example.com',
      nfs_export: '/srv/backups',
      shared: true,
    )
    expect(resource[:nfs_export]).to eq('/srv/backups')
    expect(resource[:shared]).to eq(:true)
  end

  it 'marks password as sensitive' do
    expect(type.type_definition.attributes[:password][:sensitive]).to be true
  end

  it 'marks encryption_key as sensitive' do
    expect(type.type_definition.attributes[:encryption_key][:sensitive]).to be true
  end

  it 'treats type as immutable' do
    expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
  end

  # Both are real properties again. The re-PUT-forever problem that made them
  # parameters in c0f5cd8 is solved by giving each an 'is' value to compare
  # against: password reads /etc/pve/priv/storage/<id>.pw, and encryption_key
  # compares the fingerprint PVE returns from the API.
  [:password, :encryption_key].each do |attribute|
    it "declares #{attribute} as a property so a secret-only change is enforced" do
      expect(type.attrtype(attribute)).to eq(:property)
    end
  end

  it 'accepts a Ceph RBD storage with cluster connection options' do
    resource = type.new(
      storage: 'ceph-rbd',
      type: 'rbd',
      pool: 'vm-pool',
      data_pool: 'ec-pool',
      monhost: '10.0.0.1,10.0.0.2',
      keyring: '[client.admin]\n  key = AQ...',
      krbd: true,
    )
    expect(resource[:pool]).to eq('vm-pool')
    expect(resource[:data_pool]).to eq('ec-pool')
    expect(resource[:monhost]).to eq('10.0.0.1,10.0.0.2')
    expect(resource[:krbd]).to eq(:true)
  end

  it 'accepts a Proxmox Backup Server storage with an encryption key' do
    resource = type.new(
      storage: 'pbs',
      type: 'pbs',
      server: 'pbs.example.com',
      datastore: 'main',
      encryption_key: 'autogen',
    )
    expect(resource[:datastore]).to eq('main')
    expect(resource[:encryption_key]).to eq('autogen')
  end

  it 'accepts directory storage layout and image options' do
    resource = type.new(
      storage: 'local-dir',
      type: 'dir',
      path: '/srv/storage',
      is_mountpoint: 'yes',
      create_base_path: true,
      create_subdirs: false,
      bwlimit: 'restore=10240,migration=5120',
      preallocation: 'falloc',
      sparse: true,
      nocow: false,
    )
    expect(resource[:is_mountpoint]).to eq('yes')
    expect(resource[:create_base_path]).to eq(:true)
    expect(resource[:create_subdirs]).to eq(:false)
    expect(resource[:bwlimit]).to eq('restore=10240,migration=5120')
    expect(resource[:preallocation]).to eq('falloc')
    expect(resource[:sparse]).to eq(:true)
    expect(resource[:nocow]).to eq(:false)
  end

  it 'accepts a ZFS storage with a block size' do
    resource = type.new(storage: 'zfs-pool', type: 'zfspool', pool: 'rpool/data', blocksize: '8k')
    expect(resource[:blocksize]).to eq('8k')
  end

  describe 'preallocation attribute' do
    ['off', 'metadata', 'falloc', 'full'].each do |mode|
      it "accepts #{mode}" do
        expect { type.new(storage: 's', type: 'dir', path: '/srv', preallocation: mode) }.not_to raise_error
      end
    end

    it 'rejects an unknown mode' do
      expect { type.new(storage: 's', type: 'dir', path: '/srv', preallocation: 'bogus') }.to raise_error(Puppet::ResourceError)
    end
  end
end
