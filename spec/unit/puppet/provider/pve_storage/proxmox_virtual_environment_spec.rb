# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_storage/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveStorage::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:immutable_attributes) do
    [:type, :path, :server, :nfs_export, :share, :portal, :target, :vgname, :thinpool, :pool, :datastore, :blocksize].to_h do |name|
      [name, { behaviour: :init_only }]
    end
  end
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:storage], attributes: immutable_attributes) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
    # Default: no on-node secret store, so existing examples are unaffected.
    allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:available?).and_return(false)
  end

  describe 'secret handling' do
    before(:each) do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:assert_available!)
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:storage_password).with('pbs').and_return('stored-pw')
    end

    it 'is in sync when the declared password matches priv/storage/<id>.pw' do
      expect(provider.insync?(context, 'pbs', :password, {}, password: 'stored-pw')).to be(true)
    end

    it 'is out of sync when the declared password differs' do
      expect(provider.insync?(context, 'pbs', :password, {}, password: 'rotated')).to be(false)
    end

    it 'reports a stable placeholder rather than the secret itself' do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:available?).and_return(true)
      allow(transport).to receive(:get).with(context, '/storage').and_return([{ 'storage' => 'pbs', 'type' => 'pbs' }])
      result = provider.get(context).first
      expect(result[:password]).to eq(described_class::SECRET_PLACEHOLDER)
      expect(result[:password]).not_to include('stored-pw')
    end

    it 'omits the placeholder when the store is unavailable, without raising' do
      allow(transport).to receive(:get).with(context, '/storage').and_return([{ 'storage' => 'pbs', 'type' => 'pbs' }])
      expect(provider.get(context).first).not_to have_key(:password)
    end

    describe 'encryption_key' do
      let(:key) { '{"fingerprint":"aa:bb:cc","data":"..."}' }

      it 'compares the declared key fingerprint against what the API returned' do
        expect(provider.insync?(context, 'pbs', :encryption_key, { encryption_key: 'aa:bb:cc' }, encryption_key: key)).to be(true)
      end

      it 'is out of sync when the fingerprint differs' do
        expect(provider.insync?(context, 'pbs', :encryption_key, { encryption_key: 'dd:ee:ff' }, encryption_key: key)).to be(false)
      end

      it "treats 'autogen' as satisfied whenever any key exists" do
        expect(provider.insync?(context, 'pbs', :encryption_key, { encryption_key: 'aa:bb:cc' }, encryption_key: 'autogen')).to be(true)
      end

      it "treats 'autogen' as out of sync when no key exists" do
        expect(provider.insync?(context, 'pbs', :encryption_key, {}, encryption_key: 'autogen')).to be(false)
      end

      it "treats PVE's fingerprint-less '1' marker as satisfied" do
        expect(provider.insync?(context, 'pbs', :encryption_key, { encryption_key: '1' }, encryption_key: key)).to be(true)
      end

      it 'rejects a declared key that is not valid JSON' do
        expect { provider.insync?(context, 'pbs', :encryption_key, { encryption_key: 'aa:bb:cc' }, encryption_key: 'not json') }
          .to raise_error(Puppet::ResourceError, %r{JSON formatted encryption key})
      end

      it 'never consults the secret store' do
        expect(PuppetX::ProxmoxVirtualEnvironment::SecretStore).not_to receive(:assert_available!)
        provider.insync?(context, 'pbs', :encryption_key, { encryption_key: 'aa:bb:cc' }, encryption_key: key)
      end
    end
  end

  it 'reads and maps PVE storage definitions' do
    allow(transport).to receive(:get).with(context, '/storage').and_return([
                                                                             { 'storage' => 'backup', 'type' => 'nfs', 'server' => 'nfs.example.com', 'export' => '/srv/backup', 'shared' => 1 },
                                                                           ])
    expect(provider.get(context)).to contain_exactly(
      hash_including(storage: 'backup', type: 'nfs', nfs_export: '/srv/backup', shared: true, ensure: 'present'),
    )
  end

  it 'maps Ceph/RBD and PBS attributes when reading' do
    allow(transport).to receive(:get).with(context, '/storage').and_return([
                                                                             {
                                                                               'storage' => 'ceph-rbd', 'type' => 'rbd', 'pool' => 'vm-pool', 'data-pool' => 'ec-pool',
                                                                               'monhost' => '10.0.0.1,10.0.0.2', 'krbd' => 1,
                                                                             },
                                                                             { 'storage' => 'pbs', 'type' => 'pbs', 'datastore' => 'main' },
                                                                           ])
    expect(provider.get(context)).to contain_exactly(
      hash_including(storage: 'ceph-rbd', type: 'rbd', pool: 'vm-pool', data_pool: 'ec-pool', monhost: '10.0.0.1,10.0.0.2', krbd: true),
      hash_including(storage: 'pbs', type: 'pbs', datastore: 'main'),
    )
  end

  it 'maps directory layout and image option attributes when reading' do
    allow(transport).to receive(:get).with(context, '/storage').and_return([
                                                                             {
                                                                               'storage' => 'local-dir', 'type' => 'dir', 'path' => '/srv/storage', 'is_mountpoint' => 'yes',
                                                                               'create-base-path' => 1, 'create-subdirs' => 0, 'preallocation' => 'falloc', 'sparse' => 1, 'nocow' => 0,
                                                                             },
                                                                           ])
    expect(provider.get(context)).to contain_exactly(
      hash_including(
        storage: 'local-dir', type: 'dir', is_mountpoint: 'yes', create_base_path: true,
        create_subdirs: false, preallocation: 'falloc', sparse: true, nocow: false
      ),
    )
  end

  it 'treats reordered content lists as in sync, since PVE returns them in its own canonical order' do
    expect(provider.insync?(context, 'local', :content, { content: 'backup,vztmpl,iso' }, { content: 'vztmpl,backup,iso' })).to be(true)
    expect(provider.insync?(context, 'local', :content, { content: 'backup,vztmpl' }, { content: 'vztmpl,backup,iso' })).to be(false)
  end

  it 'treats reordered node lists as in sync, since PVE returns them in its own canonical order' do
    expect(provider.insync?(context, 'local', :nodes, { nodes: 'pve1,pve2,pve3' }, { nodes: 'pve3,pve1,pve2' })).to be(true)
    expect(provider.insync?(context, 'local', :nodes, { nodes: 'pve1,pve2' }, { nodes: 'pve3,pve1,pve2' })).to be(false)
  end

  it 'delegates delete_properties comparison to the base implementation' do
    should = { delete_properties: ['nodes'] }
    expect(provider.insync?(context, 'local', :delete_properties, { nodes: 'pve1' }, should)).to be(false)
    expect(provider.insync?(context, 'local', :delete_properties, {}, should)).to be(true)
  end

  it 'creates storage through POST /storage' do
    should = { storage: 'backup', type: 'dir', path: '/srv/backup', ensure: 'present' }
    expect(transport).to receive(:post).with(context, '/storage', hash_including('storage' => 'backup', 'type' => 'dir'))
    provider.create(context, 'backup', should)
  end

  it 'never sends a delete parameter on create even when delete_properties are declared' do
    should = { storage: 'backup', type: 'dir', path: '/srv/backup', delete_properties: ['comment'], ensure: 'present' }
    expect(transport).to receive(:post) do |_ctx, path, body|
      expect(path).to eq('/storage')
      expect(body).not_to have_key('delete')
      expect(body).to include('storage' => 'backup')
    end
    provider.create(context, 'backup', should)
  end

  it 'creates a Ceph RBD storage sending pool and connection parameters' do
    should = {
      storage: 'ceph-rbd', type: 'rbd', pool: 'vm-pool', data_pool: 'ec-pool',
      monhost: '10.0.0.1,10.0.0.2', krbd: true, ensure: 'present',
    }
    expect(transport).to receive(:post).with(
      context,
      '/storage',
      hash_including('pool' => 'vm-pool', 'data-pool' => 'ec-pool', 'monhost' => '10.0.0.1,10.0.0.2', 'krbd' => true),
    )
    provider.create(context, 'ceph-rbd', should)
  end

  it 'creates a PBS storage sending the encryption key' do
    should = { storage: 'pbs', type: 'pbs', datastore: 'main', encryption_key: 'autogen', ensure: 'present' }
    expect(transport).to receive(:post).with(context, '/storage', hash_including('encryption-key' => 'autogen'))
    provider.create(context, 'pbs', should)
  end

  it 'creates directory storage sending layout and image option parameters' do
    should = {
      storage: 'local-dir', type: 'dir', path: '/srv/storage', is_mountpoint: 'yes',
      create_base_path: true, create_subdirs: false, bwlimit: 'restore=10240', preallocation: 'falloc',
      sparse: true, nocow: false, ensure: 'present',
    }
    expect(transport).to receive(:post).with(
      context,
      '/storage',
      hash_including(
        'is_mountpoint' => 'yes', 'create-base-path' => true, 'create-subdirs' => false,
        'bwlimit' => 'restore=10240', 'preallocation' => 'falloc', 'sparse' => true, 'nocow' => false
      ),
    )
    provider.create(context, 'local-dir', should)
  end

  # password is a parameter, so it never triggers an update on its own, but it
  # still rides along in the body of updates driven by other properties.
  it 'does not send immutable type and does include the declared password on update' do
    should = { storage: 'backup', type: 'pbs', username: 'root@pam', password: 'secret', disable: true, ensure: 'present' }
    expect(transport).to receive(:put).with(
      context,
      '/storage/backup',
      { 'username' => 'root@pam', 'password' => 'secret', 'disable' => true },
    )
    provider.update(context, 'backup', should)
  end

  it 'silently omits shared when the declared value matches the value PVE forces for the type' do
    should = {
      storage: 'ceph-ssd', type: 'rbd', pool: 'ceph-ssd', content: 'images,rootdir', shared: true, krbd: false, ensure: 'present',
    }
    expect(transport).to receive(:put).with(
      context,
      '/storage/ceph-ssd',
      { 'content' => 'images,rootdir', 'krbd' => false },
    )
    provider.update(context, 'ceph-ssd', should)
  end

  it 'omits shared => true on create for an inherently shared backend' do
    should = { storage: 'backup', type: 'nfs', server: 'nfs.example.com', nfs_export: '/srv/backup', shared: true, ensure: 'present' }
    expect(transport).to receive(:post) do |_ctx, path, body|
      expect(path).to eq('/storage')
      expect(body).not_to have_key('shared')
    end
    provider.create(context, 'backup', should)
  end

  it 'raises when shared => false contradicts an inherently shared backend' do
    should = { storage: 'backup', type: 'nfs', server: 'nfs.example.com', nfs_export: '/srv/backup', shared: false, ensure: 'present' }
    expect(transport).not_to receive(:post)
    expect { provider.create(context, 'backup', should) }
      .to raise_error(Puppet::ResourceError, %r{storage type 'nfs' is always shared; cannot set shared => false})
  end

  it 'raises when shared => true contradicts a purely local backend' do
    should = { storage: 'local-thin', type: 'lvmthin', vgname: 'pve', thinpool: 'data', shared: true, ensure: 'present' }
    expect(transport).not_to receive(:put)
    expect { provider.update(context, 'local-thin', should) }
      .to raise_error(Puppet::ResourceError, %r{storage type 'lvmthin' is never shared; cannot set shared => true})
  end

  it 'omits shared => false for a purely local backend where it matches the forced value' do
    should = { storage: 'local-zfs', type: 'zfspool', pool: 'rpool/data', shared: false, content: 'images', ensure: 'present' }
    expect(transport).to receive(:put).with(context, '/storage/local-zfs', { 'content' => 'images' })
    provider.update(context, 'local-zfs', should)
  end

  it 'tolerates an unset shared attribute on an unsupported backend type' do
    should = { storage: 'ceph-ssd', type: 'rbd', pool: 'ceph-ssd', content: 'images', shared: nil, ensure: 'present' }
    expect(transport).to receive(:put).with(context, '/storage/ceph-ssd', { 'content' => 'images' })
    provider.update(context, 'ceph-ssd', should)
  end

  it 'sends shared for backend types where PVE allows setting it' do
    should = { storage: 'local-dir', type: 'dir', path: '/srv/storage', shared: true, ensure: 'present' }
    expect(transport).to receive(:put).with(
      context,
      '/storage/local-dir',
      { 'shared' => true },
    )
    provider.update(context, 'local-dir', should)
  end

  it 'does not send immutable backend-identity properties on update' do
    should = {
      storage: 'local-dir', type: 'dir', path: '/srv/storage', content: 'images', disable: true, ensure: 'present',
    }
    expect(transport).to receive(:put).with(
      context,
      '/storage/local-dir',
      { 'content' => 'images', 'disable' => true },
    )
    provider.update(context, 'local-dir', should)
  end

  it 'sends delete_properties as the PVE comma-separated delete parameter' do
    should = { storage: 'backup', type: 'pbs', delete_properties: ['comment', 'nodes'], ensure: 'present' }
    expect(transport).to receive(:put).with(context, '/storage/backup', { 'delete' => 'comment,nodes' })
    provider.update(context, 'backup', should)
  end

  it 'deletes storage through DELETE /storage/{storage}' do
    expect(transport).to receive(:delete).with(context, '/storage/backup')
    provider.delete(context, 'backup')
  end
end
