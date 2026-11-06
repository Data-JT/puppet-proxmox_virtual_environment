# frozen_string_literal: true

require 'fiddle'
require 'puppet'

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxVirtualEnvironment; end

# crypt(3) verification for the password hashes in /etc/pve/priv/shadow.cfg.
#
# Deliberately scheme-agnostic: passing the stored hash back to crypt(3) as the
# *setting* makes it re-derive with the same scheme, salt and cost. PVE 9.2.6
# writes $5$ (SHA-256 crypt); the sibling PBS module sees $y$ (yescrypt). One
# call covers both, and survives PVE changing its mind.
#
# ALWAYS require this file with `require_relative` -- see config.rb for why a
# bare require breaks type autoloading inside puppetserver.
module PuppetX::ProxmoxVirtualEnvironment::Crypt
  LIBCRYPT = 'libcrypt.so.1'
  # crypt(3) signals failure with NULL or a token starting with '*'.
  FAILURE_TOKEN = '*'
  # Generous upper bound for a crypt(3) result; yescrypt hashes are the longest
  # in practice at well under 128 bytes.
  RESULT_LIMIT = 512

  # True when plaintext is the password that produced stored_hash.
  #
  # Never raises on a hash it cannot handle: a corrupt or future-scheme entry
  # reports drift instead of failing the run, so one bad shadow.cfg line cannot
  # take down an otherwise healthy catalog.
  def self.verify(plaintext, stored_hash)
    return false if stored_hash.nil? || stored_hash.to_s.empty?

    derived = hash_password(plaintext, stored_hash)
    return false if derived.nil?

    derived == stored_hash
  end

  # Returns the crypt(3) output for plaintext under the given setting, or nil
  # when crypt(3) rejects the setting (unknown scheme, salt too short).
  #
  # Note that crypt(3) accepts a bare alphanumeric string as a legacy DES salt,
  # so "rejected" is narrower than "not a recognisable hash".
  def self.hash_password(plaintext, setting)
    result = crypt_function.call(plaintext.to_s, setting.to_s)
    return nil if result.null?

    derived = result[0, RESULT_LIMIT].split("\x00", 2).first
    return nil if derived.nil? || derived.empty? || derived.start_with?(FAILURE_TOKEN)

    derived
  end

  def self.crypt_function
    @crypt_function ||= Fiddle::Function.new(
      library['crypt'],
      [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
      Fiddle::TYPE_VOIDP,
    )
  end
  private_class_method :crypt_function

  def self.library
    @library ||= Fiddle::Handle.new(LIBCRYPT)
  rescue Fiddle::DLError => error
    raise Puppet::ResourceError, "Failed to load #{LIBCRYPT} for password verification: #{error.message}"
  end
  private_class_method :library
end
