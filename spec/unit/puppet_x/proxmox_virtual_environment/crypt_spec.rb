# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/proxmox_virtual_environment/crypt'

RSpec.describe PuppetX::ProxmoxVirtualEnvironment::Crypt do
  # $5$ (SHA-256 crypt) is what PVE 9.2.6 writes into shadow.cfg.
  let(:sha256_hash) { described_class.hash_password('correct horse battery staple', '$5$cyYW6Pbt') }

  describe '.verify' do
    it 'accepts the plaintext that produced the hash' do
      expect(described_class.verify('correct horse battery staple', sha256_hash)).to be(true)
    end

    it 'rejects a different plaintext' do
      expect(described_class.verify('wrong password', sha256_hash)).to be(false)
    end

    it 'rejects rather than raises on a nil hash' do
      expect(described_class.verify('anything', nil)).to be(false)
    end

    it 'rejects rather than raises on an empty hash' do
      expect(described_class.verify('anything', '')).to be(false)
    end

    it 'rejects rather than raises on a malformed hash' do
      expect(described_class.verify('anything', 'not-a-crypt-hash')).to be(false)
    end

    it 'is scheme-agnostic: the stored hash supplies the setting' do
      expect(sha256_hash).to start_with('$5$')
      expect(described_class.verify('correct horse battery staple', sha256_hash)).to be(true)
    end
  end

  describe '.hash_password' do
    it 'is deterministic for the same plaintext and setting' do
      expect(described_class.hash_password('pw', '$5$saltsalt')).to eq(described_class.hash_password('pw', '$5$saltsalt'))
    end

    # An unknown hash scheme is the realistic failure: a shadow.cfg written by
    # a PVE whose crypt scheme this libcrypt does not implement. crypt(3)
    # returns NULL, which must surface as "cannot verify" rather than a crash.
    it 'returns nil for a hash scheme crypt(3) does not implement' do
      expect(described_class.hash_password('pw', '$z$xx')).to be_nil
    end

    it 'returns nil for a setting too short to be a salt' do
      expect(described_class.hash_password('pw', 'a')).to be_nil
    end

    # Not a bug: a bare alphanumeric string is a valid legacy DES salt, so
    # crypt(3) accepts it. verify() still reports drift because the DES output
    # never equals the setting it was derived from.
    it 'treats a bare string as a legacy DES salt rather than rejecting it' do
      expect(described_class.hash_password('pw', 'nonsense')).to eq('noufLM66ZQsGM')
      expect(described_class.verify('pw', 'nonsense')).to be(false)
    end
  end
end
