# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_sdn_dns/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveSdnDns::ProxmoxVirtualEnvironment do
  let(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:immutable_attributes) { { type: { behaviour: :init_only } } }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:dns], attributes: immutable_attributes) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
  end

  # /cluster/sdn/dns accepts neither pending nor running, and .running-config
  # has no dns section, so a second read would be a 400.
  it 'issues no pending read at all' do
    allow(transport).to receive(:get).with(context, '/cluster/sdn/dns').and_return([{ 'dns' => 'pdns1', 'type' => 'powerdns' }])

    expect(transport).not_to receive(:get).with(context, '/cluster/sdn/dns', anything)
    expect(provider.get(context).first).not_to have_key(:pending_state)
  end

  describe 'the API key' do
    before(:each) do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/dns').and_return(
        [{ 'dns' => 'pdns1', 'type' => 'powerdns', 'url' => 'http://pdns.example.com:8081', 'key' => 'stored-key' }],
      )
    end

    it 'reads the key back from the API, so it can be compared' do
      expect(provider.get(context).first[:key]).to eq('stored-key')
    end

    # The re-PUT-forever failure mode a write-only secret would have: with the
    # value round-tripping, a declared key that already matches produces no
    # change on the second run.
    it 'is in sync when the declared key matches what PVE returned' do
      expect(provider.insync?(context, 'pdns1', :key, { key: 'stored-key' }, key: 'stored-key')).to be_nil
    end

    it 'unwraps a Sensitive key for the request body' do
      expect(transport).to receive(:call).with(
        context, 'PUT', '/cluster/sdn/dns/{dns}',
        body: { 'key' => 'rotated-key' },
        path_params: { 'dns' => 'pdns1' }
      )

      provider.update(context, 'pdns1', dns: 'pdns1', type: 'powerdns', key: Puppet::Pops::Types::PSensitiveType::Sensitive.new('rotated-key'), ensure: 'present')
    end
  end

  it 'posts a create body' do
    expect(transport).to receive(:call).with(
      context, 'POST', '/cluster/sdn/dns',
      body: { 'dns' => 'pdns1', 'type' => 'powerdns', 'url' => 'http://pdns.example.com:8081', 'key' => 'secret-key', 'ttl' => 300 },
      path_params: {}
    )

    provider.create(context, 'pdns1', dns: 'pdns1', type: 'powerdns', url: 'http://pdns.example.com:8081', key: 'secret-key', ttl: 300, ensure: 'present')
  end
end
