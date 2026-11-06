# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'puppet_x/proxmox_virtual_environment/secret_store'

RSpec.describe PuppetX::ProxmoxVirtualEnvironment::SecretStore do
  around(:each) do |example|
    Dir.mktmpdir do |dir|
      described_class.priv_dir = dir
      example.run
    ensure
      described_class.priv_dir = nil
    end
  end

  let(:priv) { described_class.priv_dir }

  describe '.available?' do
    it 'is true when the priv dir exists' do
      expect(described_class.available?).to be(true)
    end

    it 'is false when the priv dir is absent' do
      described_class.priv_dir = File.join(priv, 'nope')
      expect(described_class.available?).to be(false)
    end
  end

  describe '.assert_available!' do
    it 'raises naming the path and the attribute when the priv dir is absent' do
      described_class.priv_dir = '/nonexistent/pve/priv'
      expect { described_class.assert_available!(:password) }
        .to raise_error(Puppet::ResourceError) { |error|
              expect(error.message).to include('/nonexistent/pve/priv')
              expect(error.message).to include('password')
            }
    end

    it 'does not raise when the priv dir is readable' do
      expect { described_class.assert_available!(:password) }.not_to raise_error
    end
  end

  describe '.storage_password' do
    it 'returns the stored password with the trailing newline stripped' do
      FileUtils.mkdir_p(File.join(priv, 'storage'))
      File.write(File.join(priv, 'storage', 'pbs.pw'), "s3cret-with-newline\n")
      expect(described_class.storage_password('pbs')).to eq('s3cret-with-newline')
    end

    it 'returns nil when PVE holds no password for that storage' do
      FileUtils.mkdir_p(File.join(priv, 'storage'))
      expect(described_class.storage_password('absent')).to be_nil
    end

    it 'returns nil when the storage dir itself does not exist' do
      expect(described_class.storage_password('pbs')).to be_nil
    end

    it 'refuses a storeid containing a path separator' do
      expect { described_class.storage_password('../../etc/passwd') }
        .to raise_error(Puppet::ResourceError, %r{invalid PVE object name})
    end
  end

  describe '.realm_password' do
    it 'reads the current priv/realm location' do
      FileUtils.mkdir_p(File.join(priv, 'realm'))
      File.write(File.join(priv, 'realm', 'corp.pw'), "bind-secret\n")
      expect(described_class.realm_password('corp')).to eq('bind-secret')
    end

    it 'falls back to the legacy priv/ldap location' do
      FileUtils.mkdir_p(File.join(priv, 'ldap'))
      File.write(File.join(priv, 'ldap', 'corp.pw'), "legacy-secret\n")
      expect(described_class.realm_password('corp')).to eq('legacy-secret')
    end

    it 'prefers the current location when both exist' do
      FileUtils.mkdir_p(File.join(priv, 'realm'))
      FileUtils.mkdir_p(File.join(priv, 'ldap'))
      File.write(File.join(priv, 'realm', 'corp.pw'), "current\n")
      File.write(File.join(priv, 'ldap', 'corp.pw'), "legacy\n")
      expect(described_class.realm_password('corp')).to eq('current')
    end

    it 'returns nil when neither location holds a password' do
      expect(described_class.realm_password('corp')).to be_nil
    end
  end

  describe '.user_password_hash' do
    let(:shadow) do
      <<~CFG
        portal:$5$fakesal3$ExampleFakeSha256HashNotReal03xxxxxxxxxxxxx:
        pdm.example.com:$5$fakesal1$ExampleFakeSha256HashNotReal01xxxxxxxxxxxxx:
        puppet:$5$fakesal2$ExampleFakeSha256HashNotReal02xxxxxxxxxxxxx:
      CFG
    end

    before(:each) { File.write(File.join(priv, 'shadow.cfg'), shadow) }

    it 'strips the realm and looks up the bare username' do
      expect(described_class.user_password_hash('puppet@pve'))
        .to eq('$5$fakesal2$ExampleFakeSha256HashNotReal02xxxxxxxxxxxxx')
    end

    it 'handles usernames containing dots' do
      expect(described_class.user_password_hash('pdm.example.com@pve'))
        .to eq('$5$fakesal1$ExampleFakeSha256HashNotReal01xxxxxxxxxxxxx')
    end

    it 'accepts a bare username without a realm' do
      expect(described_class.user_password_hash('portal'))
        .to eq('$5$fakesal3$ExampleFakeSha256HashNotReal03xxxxxxxxxxxxx')
    end

    it 'returns nil for a user with no shadow entry' do
      expect(described_class.user_password_hash('nobody@pve')).to be_nil
    end

    it 'returns nil when shadow.cfg does not exist' do
      FileUtils.rm_f(File.join(priv, 'shadow.cfg'))
      expect(described_class.user_password_hash('puppet@pve')).to be_nil
    end

    it 'ignores blank and malformed lines' do
      File.write(File.join(priv, 'shadow.cfg'), "\n\ngarbage-without-colon\npuppet:$5$abc$def:\n")
      expect(described_class.user_password_hash('puppet@pve')).to eq('$5$abc$def')
    end
  end

  describe '.notification_secret' do
    let(:cfg) do
      <<~CFG
        smtp: Example
        \tpassword mail-secret

        gotify: gt
        \ttoken gotify-token

        webhook: hook
        \tsecret name=api,value=dmFsdWUx
        \tsecret name=hmac,value=dmFsdWUy
      CFG
    end

    before(:each) { File.write(File.join(priv, 'notifications.cfg'), cfg) }

    it 'reads an smtp password' do
      expect(described_class.notification_secret('smtp', 'Example', 'password')).to eq('mail-secret')
    end

    it 'reads a gotify token' do
      expect(described_class.notification_secret('gotify', 'gt', 'token')).to eq('gotify-token')
    end

    it 'returns every webhook secret line joined by newline' do
      expect(described_class.notification_secret('webhook', 'hook', 'secret'))
        .to eq("name=api,value=dmFsdWUx\nname=hmac,value=dmFsdWUy")
    end

    it 'does not leak a field from a different section' do
      expect(described_class.notification_secret('smtp', 'Other', 'password')).to be_nil
    end

    it 'returns nil for an absent field' do
      expect(described_class.notification_secret('gotify', 'gt', 'password')).to be_nil
    end

    it 'returns nil when notifications.cfg does not exist' do
      FileUtils.rm_f(File.join(priv, 'notifications.cfg'))
      expect(described_class.notification_secret('smtp', 'Example', 'password')).to be_nil
    end
  end
end
