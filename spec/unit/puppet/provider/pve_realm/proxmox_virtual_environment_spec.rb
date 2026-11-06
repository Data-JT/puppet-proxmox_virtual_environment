# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_realm/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveRealm::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:immutable_attributes) do
    [:type, :username_claim].to_h { |name| [name, { behaviour: :init_only }] }
  end
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:realm], attributes: immutable_attributes) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
    allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:available?).and_return(false)
  end

  describe 'secret handling' do
    before(:each) do
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:assert_available!)
      allow(PuppetX::ProxmoxVirtualEnvironment::SecretStore).to receive(:realm_password).with('corp').and_return('bind-secret')
    end

    it 'is in sync when the declared bind_password matches the realm .pw file' do
      expect(provider.insync?(context, 'corp', :bind_password, {}, bind_password: 'bind-secret')).to be(true)
    end

    it 'is out of sync when the declared bind_password differs' do
      expect(provider.insync?(context, 'corp', :bind_password, {}, bind_password: 'rotated')).to be(false)
    end

    # client_key round-trips through the API, so returning nil hands it back to
    # Puppet's default comparison rather than consulting the store.
    it 'leaves client_key to the default comparison and never reads the store' do
      expect(PuppetX::ProxmoxVirtualEnvironment::SecretStore).not_to receive(:realm_password)
      expect(provider.insync?(context, 'corp', :client_key, { client_key: 'abc' }, client_key: 'abc')).to be_nil
    end
  end

  it 'reads realm details from /access/domains/{realm}, since the list endpoint omits most properties' do
    allow(transport).to receive(:get).with(context, '/access/domains').and_return([
                                                                                    { 'realm' => 'corp', 'type' => 'ldap' },
                                                                                  ])
    allow(transport).to receive(:get).with(context, '/access/domains/corp').and_return(
      { 'type' => 'ldap', 'base_dn' => 'dc=example,dc=com', 'user_attr' => 'uid' },
    )
    expect(provider.get(context)).to contain_exactly(
      hash_including(realm: 'corp', type: 'ldap', base_dn: 'dc=example,dc=com', user_attr: 'uid', ensure: 'present'),
    )
  end

  it 'maps AD/LDAP group sync and TLS attributes when reading' do
    allow(transport).to receive(:get).with(context, '/access/domains').and_return([
                                                                                    { 'realm' => 'corp-ad', 'type' => 'ad' },
                                                                                  ])
    allow(transport).to receive(:get).with(context, '/access/domains/corp-ad').and_return(
      {
        'type' => 'ad', 'domain' => 'ad.example.com', 'sslversion' => 'tlsv1_2',
        'secure' => 1, 'case-sensitive' => 0, 'group_dn' => 'ou=groups,dc=example,dc=com',
        'group_filter' => '(objectClass=group)', 'group_classes' => 'group', 'group_name_attr' => 'cn',
      },
    )
    expect(provider.get(context)).to contain_exactly(
      hash_including(
        realm: 'corp-ad', type: 'ad', domain: 'ad.example.com', sslversion: 'tlsv1_2',
        secure: true, case_sensitive: false, group_dn: 'ou=groups,dc=example,dc=com',
        group_filter: '(objectClass=group)', group_classes: 'group', group_name_attr: 'cn'
      ),
    )
  end

  it 'maps OpenID group-claim attributes when reading' do
    allow(transport).to receive(:get).with(context, '/access/domains').and_return([
                                                                                    { 'realm' => 'sso', 'type' => 'openid' },
                                                                                  ])
    allow(transport).to receive(:get).with(context, '/access/domains/sso').and_return(
      {
        'type' => 'openid', 'query-userinfo' => 0, 'groups-claim' => 'groups',
        'groups-autocreate' => 1, 'groups-overwrite' => 1,
      },
    )
    expect(provider.get(context)).to contain_exactly(
      hash_including(
        realm: 'sso', type: 'openid', query_userinfo: false, groups_claim: 'groups',
        groups_autocreate: true, groups_overwrite: true
      ),
    )
  end

  it 'creates a realm through the generic domains endpoint' do
    should = { realm: 'corp', type: 'ldap', server1: 'ldap.example.com', ensure: 'present' }
    expect(transport).to receive(:post).with(context, '/access/domains', hash_including('realm' => 'corp', 'type' => 'ldap'))
    provider.create(context, 'corp', should)
  end

  it 'creates an AD realm sending domain, TLS and group sync parameters' do
    should = {
      realm: 'corp-ad', type: 'ad', server1: 'ad.example.com', domain: 'ad.example.com',
      sslversion: 'tlsv1_2', secure: true, case_sensitive: false,
      group_dn: 'ou=groups,dc=example,dc=com', ensure: 'present',
    }
    expect(transport).to receive(:post).with(
      context,
      '/access/domains',
      hash_including(
        'domain' => 'ad.example.com', 'sslversion' => 'tlsv1_2', 'secure' => true,
        'case-sensitive' => false, 'group_dn' => 'ou=groups,dc=example,dc=com'
      ),
    )
    provider.create(context, 'corp-ad', should)
  end

  it 'creates an OpenID realm sending group-claim parameters' do
    should = {
      realm: 'sso', type: 'openid', issuer_url: 'https://sso.example.com', client_id: 'proxmox',
      query_userinfo: false, groups_claim: 'groups', groups_autocreate: true, groups_overwrite: true,
      ensure: 'present',
    }
    expect(transport).to receive(:post).with(
      context,
      '/access/domains',
      hash_including(
        'query-userinfo' => false, 'groups-claim' => 'groups',
        'groups-autocreate' => true, 'groups-overwrite' => true
      ),
    )
    provider.create(context, 'sso', should)
  end

  it 'omits immutable type on update and deletes by realm' do
    should = { realm: 'corp', type: 'ldap', comment: 'Corporate LDAP', ensure: 'present' }
    expect(transport).to receive(:put).with(context, '/access/domains/corp', { 'comment' => 'Corporate LDAP' })
    provider.update(context, 'corp', should)
    expect(transport).to receive(:delete).with(context, '/access/domains/corp')
    provider.delete(context, 'corp')
  end

  it 'omits immutable username_claim on update' do
    should = { realm: 'example', type: 'openid', username_claim: 'username', comment: 'OIDC', ensure: 'present' }
    expect(transport).to receive(:put).with(context, '/access/domains/example', { 'comment' => 'OIDC' })
    provider.update(context, 'example', should)
  end
end
