# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_sdn_dns'

RSpec.describe 'pve_sdn_dns type' do
  let(:type) { Puppet::Type.type(:pve_sdn_dns) }

  it 'is registered with dns as the namevar' do
    expect(type.key_attributes).to eq([:dns])
  end

  it 'treats type as immutable' do
    expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
  end

  it 'accepts a PowerDNS backend' do
    resource = type.new(dns: 'pdns1', type: 'powerdns', url: 'http://pdns.example.com:8081/api/v1/servers/localhost', key: 'secret-key', ttl: 300)
    expect(resource[:url]).to eq('http://pdns.example.com:8081/api/v1/servers/localhost')
    expect(resource[:ttl]).to eq(300)
  end

  it 'rejects a backend type PVE does not implement' do
    expect { type.new(dns: 'pdns1', type: 'bind') }.to raise_error(Puppet::ResourceError)
  end

  it 'marks key as sensitive so Puppet redacts it in reports' do
    expect(type.type_definition.attributes[:key][:sensitive]).to be true
  end

  # PVE returns the key verbatim from GET /cluster/sdn/dns -- sdn_dns_config
  # hands back the whole section unfiltered -- so unlike a genuinely write-only
  # secret it can be compared directly and drift is detected.
  it 'declares key as a property, because PVE returns it and it can go insync' do
    expect(type.attrtype(:key)).to eq(:property)
  end

  it 'has no pending_state, because a DNS backend change takes effect immediately' do
    expect(type.type_definition.attributes).not_to have_key(:pending_state)
  end
end
