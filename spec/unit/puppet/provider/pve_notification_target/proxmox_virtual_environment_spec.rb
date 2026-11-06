# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_base_provider'
require 'puppet/provider/pve_notification_target/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveNotificationTarget::ProxmoxVirtualEnvironment do
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
    allow(mock_type).to receive(:namevars).and_return([:name])
    allow(context).to receive(:notice)
    allow(context).to receive(:err)
    allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:available?).and_return(false)
  end

  describe 'secret handling' do
    before(:each) { allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:assert_available!) }

    it 'is in sync when the declared smtp_password matches the stored one' do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore)
        .to receive(:notification_secret).with('smtp', 'mail', 'password').and_return('mail-secret')
      expect(provider.insync?(context, 'mail', :smtp_password, { type: 'smtp' }, smtp_password: 'mail-secret')).to be(true)
    end

    it 'is out of sync when the declared smtp_password differs' do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore)
        .to receive(:notification_secret).with('smtp', 'mail', 'password').and_return('old')
      expect(provider.insync?(context, 'mail', :smtp_password, { type: 'smtp' }, smtp_password: 'mail-secret')).to be(false)
    end

    it 'is in sync when the declared gotify token matches' do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore)
        .to receive(:notification_secret).with('gotify', 'gt', 'token').and_return('tok')
      expect(provider.insync?(context, 'gt', :token, { type: 'gotify' }, token: 'tok')).to be(true)
    end

    it 'falls back to the declared type when discovery returned nothing' do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore)
        .to receive(:notification_secret).with('smtp', 'mail', 'password').and_return('mail-secret')
      expect(provider.insync?(context, 'mail', :smtp_password, {}, type: 'smtp', smtp_password: 'mail-secret')).to be(true)
    end

    describe 'webhook secret' do
      let(:stored) { "name=api,value=#{Base64.strict_encode64('v1')}\nname=hmac,value=#{Base64.strict_encode64('v2')}" }

      before(:each) do
        allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore)
          .to receive(:notification_secret).with('webhook', 'hook', 'secret').and_return(stored)
      end

      it 'is in sync regardless of declaration order' do
        should = { secret: [{ 'name' => 'hmac', 'value' => 'v2' }, { 'name' => 'api', 'value' => 'v1' }] }
        expect(provider.insync?(context, 'hook', :secret, { type: 'webhook' }, should)).to be(true)
      end

      it 'is out of sync when a value changed' do
        should = { secret: [{ 'name' => 'api', 'value' => 'rotated' }, { 'name' => 'hmac', 'value' => 'v2' }] }
        expect(provider.insync?(context, 'hook', :secret, { type: 'webhook' }, should)).to be(false)
      end

      it 'is out of sync when a secret was added' do
        should = { secret: [{ 'name' => 'api', 'value' => 'v1' }, { 'name' => 'hmac', 'value' => 'v2' }, { 'name' => 'extra', 'value' => 'v3' }] }
        expect(provider.insync?(context, 'hook', :secret, { type: 'webhook' }, should)).to be(false)
      end
    end
  end

  def stub_all_empty
    ['sendmail', 'smtp', 'gotify', 'webhook'].each do |t|
      allow(mock_transport).to receive(:get).with(context, "/cluster/notifications/endpoints/#{t}").and_return([])
    end
  end

  describe '#get' do
    it 'returns [] when all endpoints return nil' do
      ['sendmail', 'smtp', 'gotify', 'webhook'].each do |t|
        allow(mock_transport).to receive(:get).with(context, "/cluster/notifications/endpoints/#{t}").and_return(nil)
      end
      expect(provider.get(context)).to eq([])
    end

    it 'queries all four endpoint types' do
      ['sendmail', 'smtp', 'gotify', 'webhook'].each do |t|
        expect(mock_transport).to receive(:get).with(context, "/cluster/notifications/endpoints/#{t}").and_return([])
      end
      provider.get(context)
    end

    it 'maps a sendmail endpoint to a Puppet resource hash' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/sendmail')
                                            .and_return([{ 'name' => 'mail-admin', 'mailto' => ['admin@example.com'], 'comment' => 'admin mail' }])

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(
          name:    'mail-admin',
          type:    'sendmail',
          mailto:  ['admin@example.com'],
          comment: 'admin mail',
          ensure:  'present',
        ),
      )
    end

    it 'maps an smtp endpoint including server and from-address' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/smtp')
                                            .and_return([{ 'name' => 'smtp-relay', 'server' => 'smtp.example.com', 'from-address' => 'PVE@example.com' }])

      result = provider.get(context)
      expect(result.first).to include(
        name:         'smtp-relay',
        type:         'smtp',
        server:       'smtp.example.com',
        from_address: 'PVE@example.com',
      )
    end

    it 'maps a gotify endpoint' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/gotify')
                                            .and_return([{ 'name' => 'gotify', 'server' => 'https://gotify.example.com' }])

      result = provider.get(context)
      expect(result.first).to include(name: 'gotify', type: 'gotify', server: 'https://gotify.example.com')
    end

    it 'maps a webhook endpoint' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/webhook')
                                            .and_return([{
                                                          'name' => 'wh',
          'url' => 'https://hooks.example.com',
          'method' => 'post',
          'body' => 'eyJ0ZXh0Ijoie3ttZXNzYWdlfX0ifQ==',
          'header' => ['name=Content-Type,value=YXBwbGljYXRpb24vanNvbg=='],
                                                        }])

      result = provider.get(context)
      expect(result.first).to include(
        name: 'wh',
        type: 'webhook',
        url: 'https://hooks.example.com',
        http_method: 'post',
        body: '{"text":"{{message}}"}',
        header: [{ 'name' => 'Content-Type', 'value' => 'application/json' }],
      )
    end

    it 'converts disable boolean true' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/sendmail')
                                            .and_return([{ 'name' => 'x', 'disable' => true }])
      expect(provider.get(context).first[:disable]).to be(true)
    end

    it 'converts disable boolean false' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/sendmail')
                                            .and_return([{ 'name' => 'x', 'disable' => false }])
      expect(provider.get(context).first[:disable]).to be(false)
    end

    it 'populates the internal type cache for use by delete' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/smtp')
                                            .and_return([{ 'name' => 'smtp-relay' }])

      provider.get(context)

      expect(mock_transport).to receive(:delete).with(context, '/cluster/notifications/endpoints/smtp/smtp-relay')
      provider.delete(context, 'smtp-relay')
    end

    it 'merges results from multiple endpoint types' do
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/sendmail')
                                            .and_return([{ 'name' => 'sm1' }])
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/smtp')
                                            .and_return([{ 'name' => 'smtp1' }])
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/gotify')
                                            .and_return([])
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/webhook')
                                            .and_return([])

      expect(provider.get(context).length).to eq(2)
    end
  end

  describe '#create' do
    it 'posts to the sendmail endpoint' do
      should = { name: 'mail-admin', type: 'sendmail', mailto: ['a@b.com'], ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/cluster/notifications/endpoints/sendmail')
        expect(body).to include('name' => 'mail-admin', 'mailto' => ['a@b.com'])
      end
      provider.create(context, 'mail-admin', should)
    end

    it 'posts to the smtp endpoint' do
      should = { name: 'relay', type: 'smtp', server: 'smtp.example.com',
                 from_address: 'PVE@example.com', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/cluster/notifications/endpoints/smtp')
        expect(body).to include('server' => 'smtp.example.com', 'from-address' => 'PVE@example.com')
      end
      provider.create(context, 'relay', should)
    end

    it 'posts to the gotify endpoint' do
      should = { name: 'gotify', type: 'gotify', server: 'https://gotify.example.com', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, _body|
        expect(path).to eq('/cluster/notifications/endpoints/gotify')
      end
      provider.create(context, 'gotify', should)
    end

    it 'posts to the webhook endpoint' do
      should = { name: 'wh', type: 'webhook', url: 'https://hooks.example.com',
                 http_method: 'post', body: '{"text":"{{message}}"}',
                 header: [{ 'name' => 'Content-Type', 'value' => 'application/json' }],
                 ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, path, body|
        expect(path).to eq('/cluster/notifications/endpoints/webhook')
        expect(body).to include(
          'url' => 'https://hooks.example.com',
          'method' => 'post',
          'body' => 'eyJ0ZXh0Ijoie3ttZXNzYWdlfX0ifQ==',
          'header' => ['name=Content-Type,value=YXBwbGljYXRpb24vanNvbg=='],
        )
      end
      provider.create(context, 'wh', should)
    end

    it 'excludes type and ensure from the POST body' do
      should = { name: 'mail-admin', type: 'sendmail', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('type')
        expect(body).not_to have_key('ensure')
      end
      provider.create(context, 'mail-admin', should)
    end

    it 'includes smtp_password as password in the POST body' do
      should = { name: 'relay', type: 'smtp', smtp_password: 'secret', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('password' => 'secret')
      end
      provider.create(context, 'relay', should)
    end

    it 'unwraps a Sensitive smtp_password' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret')
      should = { name: 'relay', type: 'smtp', smtp_password: sensitive, ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body['password']).to eq('secret')
      end
      provider.create(context, 'relay', should)
    end

    it 'includes token in the POST body for gotify' do
      should = { name: 'gotify', type: 'gotify', token: 'mytoken', ensure: 'present' }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).to include('token' => 'mytoken')
      end
      provider.create(context, 'gotify', should)
    end

    it 'excludes nil optional attributes from the POST body' do
      should = { name: 'mail-admin', type: 'sendmail', ensure: 'present',
                 comment: nil, author: nil, disable: nil }
      expect(mock_transport).to receive(:post) do |_ctx, _path, body|
        expect(body).not_to have_key('comment')
        expect(body).not_to have_key('author')
        expect(body).not_to have_key('disable')
      end
      provider.create(context, 'mail-admin', should)
    end
  end

  describe '#update' do
    it 'puts to the correct endpoint path' do
      should = { name: 'mail-admin', type: 'sendmail', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, path, _body|
        expect(path).to eq('/cluster/notifications/endpoints/sendmail/mail-admin')
      end
      provider.update(context, 'mail-admin', should)
    end

    it 'excludes name and ensure from the PUT body' do
      should = { name: 'relay', type: 'smtp', server: 'smtp.example.com', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).not_to have_key('name')
        expect(body).not_to have_key('ensure')
      end
      provider.update(context, 'relay', should)
    end

    it 'includes smtp_password in the body of an update driven by other properties' do
      should = { name: 'relay', type: 'smtp', smtp_password: 'newsecret', ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('password' => 'newsecret')
      end
      provider.update(context, 'relay', should)
    end

    it 'sends delete_properties as the PVE array delete parameter' do
      should = { name: 'relay', type: 'smtp', delete_properties: ['comment', 'username'], ensure: 'present' }
      expect(mock_transport).to receive(:put) do |_ctx, _path, body|
        expect(body).to include('delete' => ['comment', 'username'])
      end
      provider.update(context, 'relay', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to the correct endpoint using the cached type' do
      stub_all_empty
      allow(mock_transport).to receive(:get).with(context, '/cluster/notifications/endpoints/smtp')
                                            .and_return([{ 'name' => 'relay' }])
      provider.get(context)

      expect(mock_transport).to receive(:delete).with(context, '/cluster/notifications/endpoints/smtp/relay')
      provider.delete(context, 'relay')
    end

    it 'raises instead of building a malformed URL when the target type was never discovered' do
      expect(mock_transport).not_to receive(:delete)
      expect { provider.delete(context, 'ghost') }
        .to raise_error(Puppet::ResourceError, %r{unknown notification target type for 'ghost'})
    end
  end
end
