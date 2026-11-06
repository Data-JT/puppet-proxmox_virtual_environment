# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_group'

RSpec.describe 'pve_group type' do
  let(:type) { Puppet::Type.type(:pve_group) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :groupid as the namevar' do
    expect(type.key_attributes).to include(:groupid)
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(groupid: 'admins', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(groupid: 'admins', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'comment attribute' do
    it 'is settable' do
      resource = type.new(groupid: 'admins', comment: 'Example admins')
      expect(resource[:comment]).to eq('Example admins')
    end
  end

  describe 'members attribute' do
    it 'is read-only' do
      expect(type.type_definition.attributes[:members][:behaviour]).to eq(:read_only)
    end

    it 'is not required to declare a resource' do
      expect { type.new(groupid: 'admins') }.not_to raise_error
    end
  end
end
