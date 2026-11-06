# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'proxmox_virtual_environment', type: :class do
  let(:pre_condition) do
    <<~PUPPET
      pve_storage { 'ordered':
        type => 'dir',
        path => '/tmp/ordered',
      }
    PUPPET
  end
  let(:facts) { YAML.safe_load_file(File.join(__dir__, '..', 'default_facts.yml')) }
  let(:secret_value) { 'supersecrettoken' }
  let(:default_config_file) { File.join(Puppet.settings[:confdir], 'pve_transport.yaml') }
  let(:params) do
    {
      token_id: 'root@pam!puppet',
      token_secret: sensitive(secret_value),
      cluster_manager: 'pve01.example.com',
    }
  end

  it { is_expected.to compile.with_all_deps }

  it 'writes a sensitive PVE transport configuration' do
    resource = catalogue.resource('File', default_config_file)
    expect(resource[:owner]).to eq('root')
    expect(resource[:group]).to eq('root')
    expect(resource[:mode]).to eq('0600')
    expect(resource.sensitive_parameters).to include(:content)
    expect(resource[:content]).to include("cluster_manager: 'pve01.example.com'")
  end

  it 'orders PVE resources after the transport class' do
    is_expected.to contain_pve_storage('ordered').that_requires("File[#{default_config_file}]")
  end

  context 'with custom connection parameters' do
    let(:params) do
      super().merge(
        host: 'pve.example.com',
        port: 9006,
        ssl_verify: true,
        ssl_ca_file: '/etc/ssl/certs/my-ca.crt',
      )
    end

    it { is_expected.to compile.with_all_deps }
  end

  context 'with custom config_file' do
    let(:params) { super().merge(config_file: '/opt/pve_transport.yaml') }

    it { is_expected.to contain_file('/opt/pve_transport.yaml').with('mode' => '0600') }
    it { is_expected.to contain_file(default_config_file).with('ensure' => 'link', 'target' => '/opt/pve_transport.yaml') }

    it 'still orders PVE resources after the transport config' do
      is_expected.to contain_pve_storage('ordered').that_requires("File[#{default_config_file}]")
    end
  end

  context 'with the default config_file' do
    it 'manages no symlink' do
      expect(catalogue.resource('File', default_config_file)[:ensure]).to eq('file')
    end
  end

  # The default path follows the AGENT's confdir (fact), not the compiling
  # server's $settings::confdir: an AIO server compiling for a Debian agent
  # must not place the file, or a link, under /etc/puppetlabs/puppet there.
  context 'when the agent reports a different confdir than the server' do
    let(:facts) { YAML.safe_load_file(File.join(__dir__, '..', 'default_facts.yml')).merge(proxmox_virtual_environment_confdir: '/etc/puppet') }

    it { is_expected.to contain_file('/etc/puppet/pve_transport.yaml').with('ensure' => 'file', 'mode' => '0600') }
    it { is_expected.not_to contain_file(default_config_file) }

    context 'with custom config_file' do
      let(:params) { super().merge(config_file: '/opt/pve_transport.yaml') }

      it { is_expected.to contain_file('/etc/puppet/pve_transport.yaml').with('ensure' => 'link', 'target' => '/opt/pve_transport.yaml') }
      it { is_expected.not_to contain_file(default_config_file) }
    end
  end

  context 'with a malformed token_id' do
    let(:params) { super().merge(token_id: 'root-pam-puppet') }

    it { is_expected.to compile.and_raise_error(%r{token_id}) }
  end

  context 'with a relative ssl_ca_file' do
    let(:params) { super().merge(ssl_ca_file: 'certs/ca.crt') }

    it { is_expected.to compile.and_raise_error(%r{ssl_ca_file}) }
  end

  context 'with a relative config_file' do
    let(:params) { super().merge(config_file: 'relative/pve_transport.yaml') }

    it { is_expected.to compile.and_raise_error(%r{config_file}) }
  end

  context 'with values containing YAML-hostile characters' do
    let(:secret_value) { %(sup'er"secret\\token) }
    let(:params) do
      super().merge(
        host: %(evil"host's\\value),
        token_id: %(root@pam!ev"il's\\token),
        cluster_manager: %(pve's"cluster\\manager),
        ssl_ca_file: %(/etc/ssl/certs/evil"ca's\\file.pem),
      )
    end

    it 'round-trips through YAML without corruption' do
      resource = catalogue.resource('File', default_config_file)
      loaded = YAML.safe_load(resource[:content])

      expect(loaded['host']).to eq(%(evil"host's\\value))
      expect(loaded['token_id']).to eq(%(root@pam!ev"il's\\token))
      expect(loaded['token_secret']).to eq(secret_value)
      expect(loaded['cluster_manager']).to eq(%(pve's"cluster\\manager))
      expect(loaded['ssl_ca_file']).to eq(%(/etc/ssl/certs/evil"ca's\\file.pem))
      expect(loaded['port']).to eq(8006)
      expect(loaded['ssl_verify']).to eq(true)
    end
  end
end
