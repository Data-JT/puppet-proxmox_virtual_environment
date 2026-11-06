# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_base_provider'
require 'puppet/provider/pve_ha_resource/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveHaResource::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:sid]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
  end

  describe '#get' do
    it 'maps the API response to Puppet resource hashes' do
      allow(transport).to receive(:get).with(context, '/cluster/ha/resources').and_return([
                                                                                            { 'sid' => 'vm:103', 'state' => 'started', 'max_restart' => 3,
                                                                                              'max_relocate' => 3, 'type' => 'vm', 'digest' => 'abc123' },
                                                                                          ])
      expect(provider.get(context)).to contain_exactly(
        hash_including(sid: 'vm:103', state: 'started', max_restart: 3, max_relocate: 3, ensure: 'present'),
      )
    end

    # digest is recomputed cluster-wide on any HA edit, and type is rejected by
    # the update endpoint. Mapping either would manufacture permanent drift.
    it 'ignores the digest and type fields PVE returns' do
      allow(transport).to receive(:get).with(context, '/cluster/ha/resources').and_return([
                                                                                            { 'sid' => 'vm:103', 'state' => 'started', 'type' => 'vm', 'digest' => 'abc123' },
                                                                                          ])
      result = provider.get(context).first
      expect(result).not_to have_key(:digest)
      expect(result).not_to have_key(:type)
    end

    it 'returns [] when the API returns nil' do
      allow(transport).to receive(:get).with(context, '/cluster/ha/resources').and_return(nil)
      expect(provider.get(context)).to eq([])
    end
  end

  describe '#create' do
    it 'posts to /cluster/ha/resources including the sid' do
      should = { sid: 'vm:114', state: 'started', max_restart: 3, ensure: 'present' }
      expect(transport).to receive(:post).with(
        context,
        '/cluster/ha/resources',
        hash_including('sid' => 'vm:114', 'state' => 'started', 'max_restart' => 3),
      )
      provider.create(context, 'vm:114', should)
    end
  end

  describe '#update' do
    it 'puts to /cluster/ha/resources/{sid} without the namevar' do
      should = { sid: 'vm:114', state: 'stopped', ensure: 'present' }
      expect(transport).to receive(:put) do |_ctx, path, body|
        expect(path).to eq('/cluster/ha/resources/vm:114')
        expect(body).to include('state' => 'stopped')
        expect(body).not_to have_key('sid')
      end
      provider.update(context, 'vm:114', should)
    end
  end

  describe '#delete' do
    it 'sends DELETE to /cluster/ha/resources/{sid}' do
      expect(transport).to receive(:delete).with(context, '/cluster/ha/resources/vm:114')
      provider.delete(context, 'vm:114')
    end
  end
end
