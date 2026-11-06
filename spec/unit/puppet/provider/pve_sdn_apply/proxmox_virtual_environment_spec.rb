# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_sdn_apply/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveSdnApply::ProxmoxVirtualEnvironment do
  let(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:name], attributes: {}) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type) }
  let(:upid) { 'UPID:node1:0000ABCD:00112233:66AA0000:reloadnetworkall::root@pam:' }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
    allow(context).to receive(:warning)
    allow(provider).to receive(:sleep)

    ['zones', 'vnets', 'controllers'].each do |kind|
      allow(transport).to receive(:get).with(context, "/cluster/sdn/#{kind}", { 'pending' => 1 }).and_return([])
    end
    allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets').and_return([])
  end

  describe 'get' do
    it 'reports applied when nothing differs from the running configuration' do
      result = provider.get(context).first
      expect(result).to include(name: 'sdn', ensure: 'present', applied: true, pending_objects: [])
    end

    it 'reports not applied and names each pending object' do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/zones', { 'pending' => 1 })
                                       .and_return([{ 'zone' => 'zone1', 'state' => 'changed', 'pending' => { 'peers' => '10.1.0.1' } }])
      allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets', { 'pending' => 1 })
                                       .and_return([{ 'vnet' => 'vnet1', 'state' => 'new', 'pending' => {} }])

      result = provider.get(context).first
      expect(result[:applied]).to be(false)
      expect(result[:pending_objects]).to contain_exactly('zones/zone1: changed', 'vnets/vnet1: new')
    end

    it 'ignores objects PVE reports without a pending state' do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/zones', { 'pending' => 1 })
                                       .and_return([{ 'zone' => 'zone1', 'type' => 'simple' }])

      expect(provider.get(context).first).to include(applied: true, pending_objects: [])
    end

    it 'walks each VNet for pending subnets' do
      allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets').and_return([{ 'vnet' => 'vnet1' }])
      allow(transport).to receive(:get).with(context, '/cluster/sdn/vnets/vnet1/subnets', { 'pending' => 1 })
                                       .and_return([{ 'subnet' => 'zone1-10.0.0.0-24', 'state' => 'new', 'pending' => {} }])

      expect(provider.get(context).first[:pending_objects]).to eq(['subnets/zone1-10.0.0.0-24: new'])
    end

    # IPAM and DNS backends have no running-config section and take effect
    # immediately, so counting them would make this resource permanently dirty.
    it 'never consults ipams or dns' do
      expect(transport).not_to receive(:get).with(context, '/cluster/sdn/ipams', any_args)
      expect(transport).not_to receive(:get).with(context, '/cluster/sdn/dns', any_args)
      provider.get(context)
    end
  end

  describe 'update' do
    it 'puts the cluster-wide apply and warns that networking reloads' do
      allow(transport).to receive(:call).with(context, 'PUT', '/cluster/sdn', body: nil, path_params: {}).and_return(upid)
      allow(transport).to receive(:call).with(context, 'GET', '/nodes/{node}/tasks/{upid}/status', path_params: { node: 'node1', upid: upid })
                                        .and_return({ 'status' => 'stopped', 'exitstatus' => 'OK' })

      expect(context).to receive(:warning).with(%r{reloads networking on every cluster node})

      provider.update(context, 'sdn', applied: true, wait: true, timeout: 300)
    end

    it 'waits for the worker and fails the resource when the apply fails' do
      allow(transport).to receive(:call).with(context, 'PUT', '/cluster/sdn', body: nil, path_params: {}).and_return(upid)
      allow(transport).to receive(:call).with(context, 'GET', '/nodes/{node}/tasks/{upid}/status', path_params: { node: 'node1', upid: upid })
                                        .and_return({ 'status' => 'stopped', 'exitstatus' => 'command failed with exit code 2' })

      expect { provider.update(context, 'sdn', applied: true, wait: true, timeout: 300) }
        .to raise_error(Puppet::ResourceError, %r{SDN apply task .* failed: command failed with exit code 2})
    end

    it 'polls until the worker stops' do
      allow(transport).to receive(:call).with(context, 'PUT', '/cluster/sdn', body: nil, path_params: {}).and_return(upid)
      expect(transport).to receive(:call).with(context, 'GET', '/nodes/{node}/tasks/{upid}/status', path_params: { node: 'node1', upid: upid })
                                         .twice.and_return({ 'status' => 'running' }, { 'status' => 'stopped', 'exitstatus' => 'OK' })

      provider.update(context, 'sdn', applied: true, wait: true, timeout: 300)
    end

    it 'falls back to DEFAULT_TIMEOUT when timeout is unset' do
      allow(transport).to receive(:call).with(context, 'PUT', '/cluster/sdn', body: nil, path_params: {}).and_return(upid)
      allow(transport).to receive(:call).with(context, 'GET', '/nodes/{node}/tasks/{upid}/status', path_params: { node: 'node1', upid: upid })
                                        .and_return({ 'status' => 'running' })
      stub_const("#{described_class}::DEFAULT_TIMEOUT", 0)

      expect { provider.update(context, 'sdn', applied: true, wait: true) }
        .to raise_error(Puppet::ResourceError, %r{Timed out after 0s})
    end

    it 'gives up once the timeout elapses' do
      allow(transport).to receive(:call).with(context, 'PUT', '/cluster/sdn', body: nil, path_params: {}).and_return(upid)
      allow(transport).to receive(:call).with(context, 'GET', '/nodes/{node}/tasks/{upid}/status', path_params: { node: 'node1', upid: upid })
                                        .and_return({ 'status' => 'running' })

      expect { provider.update(context, 'sdn', applied: true, wait: true, timeout: 0) }
        .to raise_error(Puppet::ResourceError, %r{Timed out after 0s waiting for SDN apply task})
    end

    it 'does not poll when waiting is switched off' do
      allow(transport).to receive(:call).with(context, 'PUT', '/cluster/sdn', body: nil, path_params: {}).and_return(upid)

      expect(transport).not_to receive(:call).with(context, 'GET', '/nodes/{node}/tasks/{upid}/status', any_args)

      provider.update(context, 'sdn', applied: true, wait: false, timeout: 300)
    end

    it 'rejects a task ID it cannot parse a node out of' do
      allow(transport).to receive(:call).with(context, 'PUT', '/cluster/sdn', body: nil, path_params: {}).and_return('not-a-upid')

      expect { provider.update(context, 'sdn', applied: true, wait: true, timeout: 300) }
        .to raise_error(Puppet::ResourceError, %r{unusable task ID})
    end

    it 'refuses to be driven to applied => false' do
      expect { provider.update(context, 'sdn', applied: false, wait: true, timeout: 300) }
        .to raise_error(Puppet::ResourceError, %r{only supports applied => true})
    end

    it 'turns a locked configuration into an actionable error' do
      allow(transport).to receive(:call).with(context, 'PUT', '/cluster/sdn', body: nil, path_params: {})
                                        .and_raise(Puppet::ResourceError, 'PVE API error 500 on /cluster/sdn: invalid lock token provided!')

      expect { provider.update(context, 'sdn', applied: true, wait: true, timeout: 300) }
        .to raise_error(Puppet::ResourceError, %r{locked by another client})
    end
  end

  describe 'lifecycle' do
    it 'cannot be created' do
      expect { provider.create(context, 'sdn', {}) }.to raise_error(Puppet::ResourceError, %r{cannot be created})
    end

    it 'cannot be deleted' do
      expect { provider.delete(context, 'sdn') }.to raise_error(Puppet::ResourceError, %r{cannot be removed})
    end
  end
end
