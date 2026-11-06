# frozen_string_literal: true

require 'open3'
require 'puppet'

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxVirtualEnvironment; end

# Sets PVE user passwords via the pveum CLI.
#
# PVE 9.2.6 marks PUT /access/password with allowtoken: 0 -- one of only five
# endpoints in the entire API to do so -- and this module authenticates purely
# with PVEAPIToken, so the REST path can never work here however the token is
# privileged. pveum runs locally as root@pam instead, and performs PVE's own
# hashing and pmxcfs locking rather than this module reimplementing them.
#
# ALWAYS require this file with `require_relative` -- see config.rb for why a
# bare require breaks type autoloading inside puppetserver.
module PuppetX::ProxmoxVirtualEnvironment::Pveum
  COMMAND = 'pveum'
  REDACTED = '[redacted]'

  # pveum reads the password from stdin when stdin is not a tty, but
  # PVE::PTY::read_password runs with verification on, so it must be written
  # TWICE. Writing it once exits 255 with "EOF while reading password"
  # (verified on PVE 9.2.6).
  #
  # Passed on stdin rather than argv so the secret is never visible to other
  # local users via ps.
  def self.set_password(userid, password)
    plaintext = unwrap(password).to_s
    output, status = Open3.capture2e(
      COMMAND, 'passwd', userid.to_s,
      stdin_data: "#{plaintext}\n#{plaintext}\n"
    )
    return if status.success?

    raise Puppet::ResourceError,
          "#{COMMAND} passwd failed for #{userid} (exit #{status.exitstatus}): #{scrub(output, plaintext)}"
  rescue Errno::ENOENT
    raise Puppet::ResourceError,
          "#{COMMAND} was not found. Managing pve_user passwords requires the Puppet agent to run on the PVE node, " \
          'because PVE refuses API-token authentication on PUT /access/password.'
  end

  def self.unwrap(value)
    value.respond_to?(:unwrap) ? value.unwrap : value
  end
  private_class_method :unwrap

  # pveum echoes rejected input in some failure paths, so the password is
  # stripped before the message reaches a log, a report, or PuppetDB.
  def self.scrub(output, plaintext)
    text = output.to_s.strip
    return text if plaintext.empty?

    text.gsub(plaintext, REDACTED)
  end
  private_class_method :scrub
end
