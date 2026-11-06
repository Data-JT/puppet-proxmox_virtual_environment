# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pve_acl/proxmox_virtual_environment'

RSpec.describe Puppet::Provider::PveAcl::ProxmoxVirtualEnvironment do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxVirtualEnvironment') }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext') }

  before(:each) do
    allow(provider).to receive(:pve_transport).and_return(transport)
    allow(context).to receive(:notice)
  end

  it 'reads PVE ACL entries' do
    allow(transport).to receive(:get).with(context, '/access/acl').and_return([
                                                                                { 'path' => '/', 'type' => 'user', 'ugid' => 'audit@pve', 'roleid' => 'PVEAuditor', 'propagate' => 1 },
                                                                              ])
    expect(provider.get(context)).to contain_exactly(
      hash_including(acl_path: '/', ugid: 'audit@pve', role: 'PVEAuditor', propagate: true, ensure: 'present'),
    )
  end

  it 'prefixes group ugids with @ on read and composes the title accordingly' do
    allow(transport).to receive(:get).with(context, '/access/acl').and_return([
                                                                                { 'path' => '/', 'type' => 'group', 'ugid' => 'ops', 'roleid' => 'PVEAdmin', 'propagate' => 1 },
                                                                              ])
    expect(provider.get(context)).to contain_exactly(
      hash_including(acl_path: '/', ugid: '@ops', role: 'PVEAdmin', title: '/|@ops|PVEAdmin'),
    )
  end

  it 'leaves user and token ugids verbatim on read' do
    allow(transport).to receive(:get).with(context, '/access/acl').and_return([
                                                                                { 'path' => '/', 'type' => 'user', 'ugid' => 'audit@pve', 'roleid' => 'PVEAuditor' },
                                                                                { 'path' => '/', 'type' => 'token', 'ugid' => 'bot@pve!api', 'roleid' => 'PVEAuditor' },
                                                                              ])
    expect(provider.get(context)).to contain_exactly(
      hash_including(ugid: 'audit@pve'),
      hash_including(ugid: 'bot@pve!api'),
    )
  end

  it 'uses users, groups, or tokens and plural roles in PVE ACL requests' do
    expect(transport).to receive(:put).with(context, '/access/acl', hash_including('users' => 'audit@pve', 'roles' => 'PVEAuditor'))
    provider.create(context, nil, acl_path: '/', ugid: 'audit@pve', role: 'PVEAuditor', propagate: true)

    expect(transport).to receive(:put).with(context, '/access/acl', hash_including('groups' => 'ops', 'roles' => 'PVEAdmin'))
    provider.create(context, nil, acl_path: '/', ugid: '@ops', role: 'PVEAdmin')

    expect(transport).to receive(:put).with(context, '/access/acl', hash_including('tokens' => 'bot@pve!api', 'roles' => 'PVEAuditor'))
    provider.create(context, nil, acl_path: '/', ugid: 'bot@pve!api', role: 'PVEAuditor')
  end

  it 'strips the @ from group ugids on delete' do
    expect(transport).to receive(:put).with(context, '/access/acl', hash_including('groups' => 'ops', 'delete' => true))
    provider.delete(context, acl_path: '/', ugid: '@ops', role: 'PVEAdmin')
  end

  it 'sends token ugids verbatim on delete' do
    expect(transport).to receive(:put).with(context, '/access/acl', hash_including('tokens' => 'bot@pve!api', 'delete' => true))
    provider.delete(context, acl_path: '/', ugid: 'bot@pve!api', role: 'PVEAuditor')
  end
end
