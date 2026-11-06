# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_sdn_ipam'

RSpec.describe 'pve_sdn_ipam type' do
  let(:type) { Puppet::Type.type(:pve_sdn_ipam) }

  it 'is registered with ipam as the namevar' do
    expect(type.key_attributes).to eq([:ipam])
  end

  it 'treats type as immutable' do
    expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
  end

  it 'accepts a NetBox backend' do
    resource = type.new(ipam: 'netbox1', type: 'netbox', url: 'https://netbox.example.com/api', token: 'secret-token')
    expect(resource[:url]).to eq('https://netbox.example.com/api')
  end

  it 'accepts a phpIPAM backend with a section' do
    resource = type.new(ipam: 'phpipam1', type: 'phpipam', url: 'https://ipam.example.com/api', token: 'secret-token', section: 3)
    expect(resource[:section]).to eq(3)
  end

  it 'marks token as sensitive so Puppet redacts it in reports' do
    expect(type.type_definition.attributes[:token][:sensitive]).to be true
  end

  # PVE returns the token verbatim from GET /cluster/sdn/ipams -- the section
  # config is handed back unfiltered -- so unlike a genuinely write-only secret
  # it can be compared directly and drift is detected.
  it 'declares token as a property, because PVE returns it and it can go insync' do
    expect(type.attrtype(:token)).to eq(:property)
  end

  # ipams have no pending/running split.
  it 'has no pending_state, because an IPAM change takes effect immediately' do
    expect(type.type_definition.attributes).not_to have_key(:pending_state)
  end
end
