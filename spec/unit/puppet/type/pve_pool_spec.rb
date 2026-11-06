# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_pool'

RSpec.describe 'pve_pool type' do
  let(:type) { Puppet::Type.type(:pve_pool) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :poolid as the namevar' do
    expect(type.key_attributes).to include(:poolid)
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(poolid: 'Customers', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(poolid: 'Customers', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'comment attribute' do
    it 'is nil when not set' do
      expect(type.new(poolid: 'Customers')[:comment]).to be_nil
    end

    it 'is settable' do
      resource = type.new(poolid: 'Customers', comment: 'Customer VMs')
      expect(resource[:comment]).to eq('Customer VMs')
    end
  end
end
