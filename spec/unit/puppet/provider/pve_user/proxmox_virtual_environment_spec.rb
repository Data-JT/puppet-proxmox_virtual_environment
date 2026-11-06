# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_base_provider'
require 'puppet/provider/pve_user/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveUser::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:mock_transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:mock_type)      { instance_double('Puppet::ResourceApi::Type') }
  let(:context) do
    instance_double(
      'Puppet::ResourceApi::BaseContext',
      type: mock_type,
    )
  end

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(mock_transport)
    allow(mock_type).to receive(:namevars).and_return([:userid])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
    allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:available?).and_return(false)
  end

  describe 'password handling' do
    let(:hash) { PuppetX::ProxmoxVirtualEnvironment::Crypt.hash_password('hunter2', '$5$cyYW6Pbt') }

    before(:each) do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:assert_available!)
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore)
        .to receive(:user_password_hash).with('bob@pve').and_return(hash)
      allow(mock_type).to receive(:attributes).and_return({})
    end

    it 'is in sync when the declared password verifies against the stored hash' do
      expect(provider.insync?(context, 'bob@pve', :password, {}, password: 'hunter2')).to be(true)
    end

    it 'is out of sync when the declared password does not verify' do
      expect(provider.insync?(context, 'bob@pve', :password, {}, password: 'rotated')).to be(false)
    end

    it 'is out of sync when the user has no shadow entry' do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore)
        .to receive(:user_password_hash).with('bob@pve').and_return(nil)
      expect(provider.insync?(context, 'bob@pve', :password, {}, password: 'hunter2')).to be(false)
    end

    it 'enforces a changed password through pveum, not the API' do
      allow(mock_transport).to receive(:put)
      expect(PuppetX::ProxmoxVirtualEnvironment::Pveum)
        .to receive(:set_password).with('bob@pve', 'rotated')
      provider.update(context, 'bob@pve', userid: 'bob@pve', password: 'rotated', comment: 'Bob')
    end

    it 'does not call pveum when the password is already in sync' do
      allow(mock_transport).to receive(:put)
      expect(PuppetX::ProxmoxVirtualEnvironment::Pveum).not_to receive(:set_password)
      provider.update(context, 'bob@pve', userid: 'bob@pve', password: 'hunter2')
    end

    it 'never sends password in the update body' do
      allow(PuppetX::ProxmoxVirtualEnvironment::Pveum).to receive(:set_password)
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('password')
      end
      provider.update(context, 'bob@pve', userid: 'bob@pve', password: 'rotated', comment: 'Bob')
    end

    # POST /access/users permits token auth; only PUT /access/password does not.
    it 'still sends password on create, where the API permits tokens' do
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['password']).to eq('hunter2')
      end
      provider.create(context, 'bob@pve', userid: 'bob@pve', password: 'hunter2')
    end

    it 'reports a stable placeholder rather than the hash itself' do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:available?).and_return(true)
      allow(mock_transport).to receive(:get).with(context, '/access/users').and_return([{ 'userid' => 'bob@pve' }])
      expect(provider.get(context).first[:password]).to eq(described_class::SECRET_PLACEHOLDER)
    end
  end

  describe '#get' do
    it 'returns [] when the API returns nil' do
      allow(mock_transport).to receive(:get).with(context, '/access/users').and_return(nil)
      expect(provider.get(context)).to eq([])
    end

    it 'returns [] when the API returns an empty array' do
      allow(mock_transport).to receive(:get).with(context, '/access/users').and_return([])
      expect(provider.get(context)).to eq([])
    end

    it 'maps the API response to Puppet resource hashes' do
      api_data = [
        {
          'userid'    => 'john@pve',
          'comment'   => 'John Doe',
          'email'     => 'john@example.com',
          'enable'    => 1,
          'firstname' => 'John',
          'lastname'  => 'Doe',
        },
      ]
      allow(mock_transport).to receive(:get).with(context, '/access/users').and_return(api_data)

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          userid:    'john@pve',
          comment:   'John Doe',
          email:     'john@example.com',
          enable:    true,
          firstname: 'John',
          lastname:  'Doe',
          ensure:    'present',
        ),
      )
    end

    it 'raises Puppet::ResourceError on transport failure' do
      allow(mock_transport).to receive(:get).and_raise(Puppet::ResourceError, 'connection refused')
      expect { provider.get(context) }.to raise_error(Puppet::ResourceError, %r{connection refused})
    end
  end

  describe 'enable boolean round-trip' do
    it 'converts API integer 1 to Puppet true' do
      api_data = [{ 'userid' => 'user@pve', 'enable' => 1 }]
      allow(mock_transport).to receive(:get).with(context, '/access/users').and_return(api_data)

      result = provider.get(context)

      expect(result.first[:enable]).to be(true)
    end

    it 'converts API integer 0 to Puppet false' do
      api_data = [{ 'userid' => 'user@pve', 'enable' => 0 }]
      allow(mock_transport).to receive(:get).with(context, '/access/users').and_return(api_data)

      result = provider.get(context)

      expect(result.first[:enable]).to be(false)
    end

    it 'sends Puppet :true as a boolean in POST body' do
      should = { userid: 'user@pve', enable: :true, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['enable']).to eq(true)
      end
      provider.create(context, 'user@pve', should)
    end

    it 'sends Puppet :false as a boolean in POST body' do
      should = { userid: 'user@pve', enable: :false, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['enable']).to eq(false)
      end
      provider.create(context, 'user@pve', should)
    end
  end

  describe 'userid format validation' do
    it 'raises on create when userid has no realm' do
      should = { userid: 'useronly', enable: true, ensure: 'present' }
      expect { provider.create(context, 'useronly', should) }
        .to raise_error(Puppet::ResourceError, %r{userid must be in user@realm format})
    end

    it 'raises on create when userid has multiple @ signs' do
      should = { userid: 'user@realm@extra', enable: true, ensure: 'present' }
      expect { provider.create(context, 'user@realm@extra', should) }
        .to raise_error(Puppet::ResourceError, %r{userid must be in user@realm format})
    end

    it 'raises on update when userid has no realm' do
      should = { userid: 'useronly', enable: true, ensure: 'present' }
      expect { provider.update(context, 'useronly', should) }
        .to raise_error(Puppet::ResourceError, %r{userid must be in user@realm format})
    end

    it 'does not raise on create for a valid userid' do
      should = { userid: 'john@pve', enable: true, ensure: 'present' }
      allow(mock_transport).to receive(:post)
      expect { provider.create(context, 'john@pve', should) }.not_to raise_error
    end
  end

  describe '#create' do
    it 'posts to /access/users with userid' do
      should = { userid: 'john@pve', enable: true, ensure: 'present', comment: nil }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/access/users')
        expect(body).to include('userid' => 'john@pve')
      end
      provider.create(context, 'john@pve', should)
    end

    it 'excludes ensure from the POST body' do
      should = { userid: 'john@pve', enable: true, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'john@pve', should)
    end

    it 'excludes nil attributes from the POST body' do
      should = { userid: 'john@pve', enable: true, ensure: 'present', comment: nil, email: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('comment')
        expect(body).not_to have_key('email')
      end
      provider.create(context, 'john@pve', should)
    end

    it 'includes password in the POST body when provided' do
      should = { userid: 'john@pve', enable: true, ensure: 'present', password: 'hunter2' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('password' => 'hunter2')
      end
      provider.create(context, 'john@pve', should)
    end

    it 'unwraps Sensitive password before sending' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('hunter2')
      should = { userid: 'john@pve', enable: true, ensure: 'present', password: sensitive }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['password']).to eq('hunter2')
      end
      provider.create(context, 'john@pve', should)
    end

    it 'omits password key when password is not provided' do
      should = { userid: 'john@pve', enable: true, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('password')
      end
      provider.create(context, 'john@pve', should)
    end
  end

  describe '#update' do
    it 'puts to /access/users/{userid}' do
      should = { userid: 'john@pve', enable: true, ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/access/users/john@pve')
      end
      provider.update(context, 'john@pve', should)
    end

    it 'excludes userid, ensure, and nil values from the PUT body' do
      should = {
        userid:   'john@pve',
        enable:   :true,
        ensure:   'present',
        comment:  nil,
        email:    'john@example.com',
      }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('email' => 'john@example.com', 'enable' => true)
        expect(body).not_to have_key('userid')
        expect(body).not_to have_key('ensure')
        expect(body).not_to have_key('comment')
      end
      provider.update(context, 'john@pve', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /access/users/{userid}' do
      expect(mock_transport).to receive(:delete).with(context, '/access/users/john@pve')
      provider.delete(context, 'john@pve')
    end
  end

  describe '#insync?' do
    it 'treats reordered group lists as in sync, since PVE returns them in its own canonical order' do
      is = { groups: 'admins,operators,auditors' }
      should = { groups: 'operators,auditors,admins' }
      expect(provider.insync?(context, 'john@pve', :groups, is, should)).to be(true)
    end

    it 'reports a genuine difference in group membership as out of sync' do
      is = { groups: 'admins,operators' }
      should = { groups: 'operators,auditors,admins' }
      expect(provider.insync?(context, 'john@pve', :groups, is, should)).to be(false)
    end

    it 'delegates delete_properties comparison to the base implementation' do
      should = { delete_properties: ['groups'] }
      expect(provider.insync?(context, 'john@pve', :delete_properties, { groups: 'admins' }, should)).to be(false)
      expect(provider.insync?(context, 'john@pve', :delete_properties, {}, should)).to be(true)
    end

    it 'returns nil for other attributes so the Resource API falls back to default comparison' do
      expect(provider.insync?(context, 'john@pve', :comment, { comment: 'a' }, { comment: 'b' })).to be_nil
    end
  end
end
