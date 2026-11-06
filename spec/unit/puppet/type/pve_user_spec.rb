# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_user'

RSpec.describe 'pve_user type' do
  let(:type) { Puppet::Type.type(:pve_user) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :userid as the namevar' do
    expect(type.key_attributes).to include(:userid)
  end

  it 'declares the custom_insync feature so the provider insync? is consulted' do
    expect(type.type_definition.definition[:features]).to include('custom_insync')
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(userid: 'user@pve', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(userid: 'user@pve', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'enable attribute' do
    it 'defaults to true' do
      resource = type.new(userid: 'user@pve')
      expect(resource[:enable]).to eq(:true)
    end

    it 'accepts false' do
      resource = type.new(userid: 'user@pve', enable: false)
      expect(resource[:enable]).to eq(:false)
    end
  end

  describe 'optional attributes' do
    subject(:resource) { type.new(userid: 'user@pve') }

    [:comment, :email, :expire, :firstname, :lastname, :password].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end

    it 'can be declared ensure => absent without password' do
      expect { type.new(userid: 'user@pve', ensure: 'absent') }.not_to raise_error
    end
  end

  describe 'password attribute' do
    # A real property again: it is verified against the crypt(3) hash in
    # /etc/pve/priv/shadow.cfg, and enforced with pveum passwd rather than the
    # API, which refuses token auth on PUT /access/password.
    it 'is a property so a password-only change is enforced' do
      expect(type.attrtype(:password)).to eq(:property)
    end

    it 'is marked sensitive in the type definition' do
      expect(type.type_definition.attributes[:password][:sensitive]).to be(true)
    end

    it 'accepts a plain String' do
      resource = type.new(userid: 'user@pve', password: 'secret')
      expect(resource[:password]).to eq('secret')
    end

    it 'accepts a Sensitive-wrapped String' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret')
      resource = type.new(userid: 'user@pve', password: sensitive)
      expect(resource[:password]).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        userid:    'john@pve',
        comment:   'John Doe',
        email:     'john@example.com',
        enable:    false,
        expire:    1_700_000_000,
        firstname: 'John',
        lastname:  'Doe',
      )
    end

    it { expect(resource[:userid]).to eq('john@pve') }
    it { expect(resource[:comment]).to eq('John Doe') }
    it { expect(resource[:email]).to eq('john@example.com') }
    it { expect(resource[:enable]).to eq(:false) }
    it { expect(resource[:expire]).to eq(1_700_000_000) }
    it { expect(resource[:firstname]).to eq('John') }
    it { expect(resource[:lastname]).to eq('Doe') }
  end
end
