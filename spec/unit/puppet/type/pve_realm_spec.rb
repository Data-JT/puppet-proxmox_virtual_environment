# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_realm'

RSpec.describe 'pve_realm type' do
  let(:type) { Puppet::Type.type(:pve_realm) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :realm as the namevar' do
    expect(type.key_attributes).to include(:realm)
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(realm: 'myldap', type: 'ldap', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(realm: 'myldap', type: 'ldap', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'type attribute' do
    ['ldap', 'ad', 'openid'].each do |realm_type|
      it "accepts #{realm_type}" do
        expect { type.new(realm: 'r', type: realm_type) }.not_to raise_error
      end
    end

    it 'rejects an unknown type' do
      expect { type.new(realm: 'r', type: 'radius') }.to raise_error(Puppet::ResourceError)
    end

    it 'is immutable after creation' do
      expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
    end
  end

  describe 'LDAP realm' do
    subject(:resource) do
      type.new(
        realm:    'corp-ldap',
        type:     'ldap',
        server1:  'ldap.example.com',
        base_dn:  'dc=example,dc=com',
        user_attr: 'uid',
        bind_dn:  'cn=search,dc=example,dc=com',
        port:     389,
        mode:     'ldap+starttls',
        verify:   true,
        comment:  'Corporate LDAP',
      )
    end

    it { expect(resource[:realm]).to eq('corp-ldap') }
    it { expect(resource[:type]).to eq('ldap') }
    it { expect(resource[:server1]).to eq('ldap.example.com') }
    it { expect(resource[:base_dn]).to eq('dc=example,dc=com') }
    it { expect(resource[:user_attr]).to eq('uid') }
    it { expect(resource[:bind_dn]).to eq('cn=search,dc=example,dc=com') }
    it { expect(resource[:port]).to eq(389) }
    it { expect(resource[:mode]).to eq('ldap+starttls') }
    it { expect(resource[:comment]).to eq('Corporate LDAP') }
  end

  describe 'mode attribute' do
    ['ldap', 'ldap+starttls', 'ldaps'].each do |m|
      it "accepts #{m}" do
        expect { type.new(realm: 'r', type: 'ldap', mode: m) }.not_to raise_error
      end
    end

    it 'rejects an unknown mode' do
      expect { type.new(realm: 'r', type: 'ldap', mode: 'plain') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'bind_password property' do
    # Compared against /etc/pve/priv/realm/<realm>.pw, so it has a real 'is'
    # value and no longer re-PUTs forever the way c0f5cd8 guarded against.
    it 'is a property so a secret-only change is enforced' do
      expect(type.attrtype(:bind_password)).to eq(:property)
    end

    # client_key needs no store at all: PVE keeps it in the public domains.cfg
    # (Auth/OpenId.pm:110) and returns it verbatim from the API.
    it 'declares client_key as a property too' do
      expect(type.attrtype(:client_key)).to eq(:property)
    end

    it 'accepts a plain string' do
      expect { type.new(realm: 'r', type: 'ldap', bind_password: 'secret') }.not_to raise_error
    end

    it 'accepts a Sensitive value' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret')
      expect { type.new(realm: 'r', type: 'ldap', bind_password: sensitive) }.not_to raise_error
    end
  end

  describe 'AD realm' do
    subject(:resource) do
      type.new(
        realm:    'corp-ad',
        type:     'ad',
        server1:  'ad.example.com',
        base_dn:  'dc=example,dc=com',
        domain:   'ad.example.com',
        mode:     'ldaps',
        secure:   true,
        sslversion: 'tlsv1_2',
        cert:     '/etc/pve/ad-client.pem',
        certkey:  '/etc/pve/ad-client.key',
        case_sensitive: false,
        tfa:      'type=oath,digits=6',
      )
    end

    it { expect(resource[:type]).to eq('ad') }
    it { expect(resource[:server1]).to eq('ad.example.com') }
    it { expect(resource[:domain]).to eq('ad.example.com') }
    it { expect(resource[:mode]).to eq('ldaps') }
    it { expect(resource[:secure]).to eq(:true) }
    it { expect(resource[:sslversion]).to eq('tlsv1_2') }
    it { expect(resource[:cert]).to eq('/etc/pve/ad-client.pem') }
    it { expect(resource[:certkey]).to eq('/etc/pve/ad-client.key') }
    it { expect(resource[:case_sensitive]).to eq(:false) }
    it { expect(resource[:tfa]).to eq('type=oath,digits=6') }
  end

  describe 'sslversion attribute' do
    ['tlsv1', 'tlsv1_1', 'tlsv1_2', 'tlsv1_3'].each do |version|
      it "accepts #{version}" do
        expect { type.new(realm: 'r', type: 'ldap', sslversion: version) }.not_to raise_error
      end
    end

    it 'rejects an unknown version' do
      expect { type.new(realm: 'r', type: 'ldap', sslversion: 'sslv3') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'LDAP/AD group sync attributes' do
    subject(:resource) do
      type.new(
        realm:           'corp-ldap',
        type:            'ldap',
        group_dn:        'ou=groups,dc=example,dc=com',
        group_filter:    '(objectClass=group)',
        group_classes:   'group, univentionGroup',
        group_name_attr: 'cn',
      )
    end

    it { expect(resource[:group_dn]).to eq('ou=groups,dc=example,dc=com') }
    it { expect(resource[:group_filter]).to eq('(objectClass=group)') }
    it { expect(resource[:group_classes]).to eq('group, univentionGroup') }
    it { expect(resource[:group_name_attr]).to eq('cn') }
  end

  describe 'OpenID realm' do
    subject(:resource) do
      type.new(
        realm:             'sso',
        type:              'openid',
        issuer_url:        'https://sso.example.com',
        client_id:         'proxmox-backup',
        username_claim:    'email',
        autocreate:        true,
        scopes:            'openid email profile',
        comment:           'Corporate SSO',
        query_userinfo:    false,
        groups_claim:      'groups',
        groups_autocreate: true,
        groups_overwrite:  true,
      )
    end

    it { expect(resource[:type]).to eq('openid') }
    it { expect(resource[:issuer_url]).to eq('https://sso.example.com') }
    it { expect(resource[:client_id]).to eq('proxmox-backup') }
    it { expect(resource[:username_claim]).to eq('email') }
    it { expect(resource[:scopes]).to eq('openid email profile') }
    it { expect(resource[:comment]).to eq('Corporate SSO') }
    it { expect(resource[:query_userinfo]).to eq(:false) }
    it { expect(resource[:groups_claim]).to eq('groups') }
    it { expect(resource[:groups_autocreate]).to eq(:true) }
    it { expect(resource[:groups_overwrite]).to eq(:true) }
  end

  describe 'client_key parameter' do
    it 'accepts a plain string' do
      expect { type.new(realm: 'sso', type: 'openid', client_key: 'mysecret') }.not_to raise_error
    end

    it 'accepts a Sensitive value' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('mysecret')
      expect { type.new(realm: 'sso', type: 'openid', client_key: sensitive) }.not_to raise_error
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(realm: 'r', type: 'ldap') }

    [:comment, :default, :server1, :server2, :port, :domain, :bind_dn, :mode, :verify, :secure, :sslversion, :capath, :cert, :certkey,
     :case_sensitive, :filter, :sync_defaults_options, :sync_attributes, :user_classes, :tfa, :base_dn, :user_attr, :group_dn, :group_filter,
     :group_classes, :group_name_attr, :issuer_url, :client_id, :username_claim, :autocreate, :scopes, :prompt, :acr_values, :audiences,
     :query_userinfo, :groups_claim, :groups_autocreate, :groups_overwrite].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
