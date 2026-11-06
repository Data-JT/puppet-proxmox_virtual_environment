# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_api_token'

RSpec.describe 'pve_api_token type' do
  let(:type) { Puppet::Type.type(:pve_api_token) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :tokenid as the namevar' do
    expect(type.key_attributes).to include(:tokenid)
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(tokenid: 'puppet@pve!mytoken', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(tokenid: 'puppet@pve!mytoken', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'tokenid attribute' do
    it 'accepts user@realm!tokenname format' do
      expect { type.new(tokenid: 'puppet@pve!mytoken') }.not_to raise_error
    end

    it 'accepts pam realm' do
      expect { type.new(tokenid: 'root@pam!admin-token') }.not_to raise_error
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        tokenid: 'puppet@pve!mytoken',
        comment: 'Puppet automation token',
        privsep:  true,
        expire:  1_893_456_000,
        secret_file: '/etc/puppetlabs/puppet/pve-token.secret',
      )
    end

    it { expect(resource[:tokenid]).to eq('puppet@pve!mytoken') }
    it { expect(resource[:comment]).to eq('Puppet automation token') }
    it { expect(resource[:privsep]).to eq(:true) }
    it { expect(resource[:expire]).to eq(1_893_456_000) }
    it { expect(resource[:secret_file]).to eq('/etc/puppetlabs/puppet/pve-token.secret') }
  end

  describe 'secret_file parameter' do
    it 'has behaviour :parameter' do
      expect(type.attrtype(:secret_file)).to eq(:param)
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(tokenid: 'puppet@pve!mytoken') }

    [:comment, :privsep, :expire, :secret_file].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
