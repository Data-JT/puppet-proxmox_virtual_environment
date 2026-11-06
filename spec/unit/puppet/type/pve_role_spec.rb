# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_role'

RSpec.describe 'pve_role type' do
  let(:type) { Puppet::Type.type(:pve_role) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :roleid as the namevar' do
    expect(type.key_attributes).to include(:roleid)
  end

  it 'declares the custom_insync feature so the provider insync? is consulted' do
    expect(type.type_definition.definition[:features]).to include('custom_insync')
  end

  describe 'ensure attribute' do
    it 'accepts present' do
      resource = type.new(roleid: 'PackerBuild', ensure: 'present')
      expect(resource[:ensure].to_s).to eq('present')
    end

    it 'accepts absent' do
      resource = type.new(roleid: 'PackerBuild', ensure: 'absent')
      expect(resource[:ensure].to_s).to eq('absent')
    end
  end

  describe 'privs attribute' do
    it 'defaults to an empty array' do
      expect(type.new(roleid: 'PackerBuild')[:privs]).to eq([])
    end

    it 'accepts an array of privilege strings' do
      resource = type.new(roleid: 'PackerBuild', privs: ['VM.Audit', 'Datastore.AllocateSpace'])
      expect(resource[:privs]).to eq(['VM.Audit', 'Datastore.AllocateSpace'])
    end
  end
end
