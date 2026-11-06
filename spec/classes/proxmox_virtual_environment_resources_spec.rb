# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'proxmox_virtual_environment::resources', type: :class do
  let(:facts) { YAML.safe_load_file(File.join(__dir__, '..', 'default_facts.yml')) }
  let(:params) do
    {
      storages: {
        'backup' => { 'type' => 'dir', 'path' => '/mnt/storage/backup' },
      },
      users: {
        'backup@pve' => { 'enable' => true, 'groups' => 'sales' },
      },
      acls: {
        '/storage/backup|backup@pve|PackerBuild' => { 'propagate' => true },
        '/storage/backup|backup@pve!automation|PackerBuild' => { 'propagate' => true },
        '/|@sales|PackerBuild' => { 'propagate' => true },
      },
      backup_jobs: {
        'nightly' => { 'job_schedule' => 'daily', 'storage' => 'backup', 'pool' => 'Customers', 'all' => true },
      },
      notification_targets: {
        'operations' => { 'type' => 'sendmail', 'mailto' => ['ops@example.com'] },
      },
      notification_matchers: {
        'all-errors' => { 'target' => ['operations'], 'match_severity' => ['error'] },
      },
      api_tokens: {
        'backup@pve!automation' => { 'privsep' => true },
      },
      pools: {
        'Customers' => { 'comment' => 'Customer VMs' },
      },
      roles: {
        'PackerBuild' => { 'privs' => ['VM.Audit', 'Datastore.AllocateSpace'] },
      },
      groups: {
        'sales' => { 'comment' => 'Sales team' },
      },
      datacenter_config: {
        'datacenter' => { 'keyboard' => 'de', 'mac_prefix' => 'BC:24:11' },
      },
      sdn_controllers: {
        'ctrl1' => { 'type' => 'evpn', 'asn' => 65_000, 'peers' => '10.0.0.1,10.0.0.2' },
      },
      sdn_ipams: {
        'netbox1' => { 'type' => 'netbox', 'url' => 'https://ipam.example.com/api', 'token' => 'secret' },
      },
      sdn_dns: {
        'pdns1' => { 'type' => 'powerdns', 'url' => 'http://dns.example.com:8081', 'key' => 'secret' },
      },
      sdn_zones: {
        'zone1' => { 'type' => 'vxlan', 'peers' => '10.0.0.1,10.0.0.2', 'ipam' => 'netbox1', 'dns' => 'pdns1' },
        'zone2' => { 'type' => 'evpn', 'controller' => 'ctrl1', 'vrf_vxlan' => 10_000 },
      },
      sdn_vnets: {
        'vnet1' => { 'zone' => 'zone1', 'vnet_tag' => 10_100 },
      },
      sdn_subnets: {
        'vnet1|10.0.0.0/24' => { 'gateway' => '10.0.0.1', 'snat' => true },
      },
      sdn_apply: {
        'sdn' => { 'noop' => true },
      },
    }
  end

  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_pve_storage('backup').with('type' => 'dir') }
  it { is_expected.to contain_pve_user('backup@pve').with('enable' => true) }
  it { is_expected.to contain_pve_acl('/storage/backup|backup@pve|PackerBuild').with('propagate' => true) }
  it { is_expected.to contain_pve_backup_job('nightly').with('job_schedule' => 'daily', 'storage' => 'backup') }
  it { is_expected.to contain_pve_pool('Customers').with('comment' => 'Customer VMs') }
  it { is_expected.to contain_pve_role('PackerBuild').with('privs' => ['VM.Audit', 'Datastore.AllocateSpace']) }
  it { is_expected.to contain_pve_group('sales').with('comment' => 'Sales team') }
  it { is_expected.to contain_pve_datacenter_config('datacenter').with('keyboard' => 'de', 'mac_prefix' => 'BC:24:11') }

  it { is_expected.to contain_pve_user('backup@pve').that_requires('Pve_group[sales]') }
  it { is_expected.to contain_pve_api_token('backup@pve!automation').that_requires('Pve_user[backup@pve]') }
  it { is_expected.to contain_pve_acl('/storage/backup|backup@pve|PackerBuild').that_requires('Pve_user[backup@pve]') }
  it { is_expected.to contain_pve_acl('/storage/backup|backup@pve|PackerBuild').that_requires('Pve_role[PackerBuild]') }
  it { is_expected.to contain_pve_acl('/storage/backup|backup@pve!automation|PackerBuild').that_requires('Pve_api_token[backup@pve!automation]') }
  it { is_expected.to contain_pve_acl('/|@sales|PackerBuild').that_requires('Pve_group[sales]') }
  it { is_expected.to contain_pve_backup_job('nightly').that_requires('Pve_storage[backup]') }
  it { is_expected.to contain_pve_backup_job('nightly').that_requires('Pve_pool[Customers]') }
  it { is_expected.to contain_pve_notification_matcher('all-errors').that_requires('Pve_notification_target[operations]') }

  describe 'SDN' do
    it { is_expected.to contain_pve_sdn_controller('ctrl1').with('type' => 'evpn', 'asn' => 65_000) }
    it { is_expected.to contain_pve_sdn_ipam('netbox1').with('type' => 'netbox') }
    it { is_expected.to contain_pve_sdn_dns('pdns1').with('type' => 'powerdns') }
    it { is_expected.to contain_pve_sdn_zone('zone1').with('type' => 'vxlan', 'peers' => '10.0.0.1,10.0.0.2') }
    it { is_expected.to contain_pve_sdn_vnet('vnet1').with('zone' => 'zone1', 'vnet_tag' => 10_100) }
    it { is_expected.to contain_pve_sdn_subnet('vnet1|10.0.0.0/24').with('gateway' => '10.0.0.1') }
    it { is_expected.to contain_pve_sdn_apply('sdn') }

    # Ordering comes from autorequires on the types, not from edges declared
    # in this class, so it holds for hand-written manifests too.
    it { is_expected.to contain_pve_sdn_zone('zone1').that_requires('Pve_sdn_ipam[netbox1]') }
    it { is_expected.to contain_pve_sdn_zone('zone1').that_requires('Pve_sdn_dns[pdns1]') }
    it { is_expected.to contain_pve_sdn_zone('zone2').that_requires('Pve_sdn_controller[ctrl1]') }
    it { is_expected.to contain_pve_sdn_vnet('vnet1').that_requires('Pve_sdn_zone[zone1]') }
    it { is_expected.to contain_pve_sdn_subnet('vnet1|10.0.0.0/24').that_requires('Pve_sdn_vnet[vnet1]') }

    # The apply must observe every write the run made before it decides
    # whether the running configuration is up to date.
    ['Pve_sdn_controller[ctrl1]', 'Pve_sdn_zone[zone1]', 'Pve_sdn_vnet[vnet1]', 'Pve_sdn_subnet[vnet1|10.0.0.0/24]'].each do |dependency|
      it { is_expected.to contain_pve_sdn_apply('sdn').that_requires(dependency) }
    end

    # Declaring the apply with noop is the documented report-only mode.
    it 'keeps the declared apply in report-only mode' do
      expect(catalogue.resource('Pve_sdn_apply[sdn]')[:noop]).to be true
    end
  end
end
