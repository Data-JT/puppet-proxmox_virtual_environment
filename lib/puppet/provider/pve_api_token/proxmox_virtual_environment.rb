# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveApiToken; end

# Provider for pve_api_token resources via the PVE REST API.
#
# Tokens live under their owning user: /access/users/{userid}/token/{tokenname}.
# The namevar is the full token ID in user@realm!tokenname format.
class Puppet::Provider::PveApiToken::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'tokenid' => :tokenid,
      'comment' => :comment,
      'privsep' => :privsep,
      'expire'  => :expire,
      'delete'  => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:privsep]
  end

  def get(context)
    users = transport_get(context, '/access/users') || []
    users.flat_map { |user| tokens_for_user(context, user['userid']) }
  end

  def create(context, name, should)
    userid, tokenname = parse_tokenid!(name)
    # Verify the secret can be persisted BEFORE creating the token: PVE returns
    # the secret only once, so a write that fails afterwards loses it forever.
    preflight_secret_file!(should[:secret_file]) if should[:secret_file]
    context.notice("Creating API token '#{name}'")
    result = pve_transport(context).post(
      context,
      "/access/users/#{userid}/token/#{tokenname}",
      create_body(context, should.reject { |attribute, _| context.type.namevars.include?(attribute) }),
    )
    persist_secret(context, name, should[:secret_file], result)
  end

  def update(context, name, should)
    userid, tokenname = parse_tokenid!(name)
    context.notice("Updating API token '#{name}'")
    pve_transport(context).put(
      context,
      "/access/users/#{userid}/token/#{tokenname}",
      update_body(context, should),
    )
  end

  def delete(context, name)
    userid, tokenname = parse_tokenid!(name)
    context.notice("Deleting API token '#{name}'")
    pve_transport(context).delete(context, "/access/users/#{userid}/token/#{tokenname}")
  end

  private

  def preflight_secret_file!(secret_file)
    dir = File.dirname(secret_file)
    unless File.directory?(dir)
      raise Puppet::ResourceError,
            "secret_file directory '#{dir}' does not exist; create it before managing this token so the one-time API token secret can be stored"
    end
    unless File.writable?(dir)
      raise Puppet::ResourceError,
            "secret_file directory '#{dir}' is not writable; refusing to create the token because the one-time secret could not be stored"
    end
    return unless File.symlink?(secret_file)

    raise Puppet::ResourceError,
          "secret_file '#{secret_file}' is a symlink; refusing to write the one-time API token secret through a symlink"
  end

  def persist_secret(context, tokenid, secret_file, result)
    secret = result['value'] if result.is_a?(Hash)
    return unless secret

    unless secret_file
      context.warning("PVE returned the one-time secret for '#{tokenid}', but secret_file is not configured; the secret was not retained")
      return
    end

    flags = File::WRONLY | File::CREAT | File::TRUNC | File::NOFOLLOW
    File.open(secret_file, flags, 0o600) do |file|
      file.chmod(0o600)
      file.write("#{secret}\n")
    end
    context.notice("Stored the one-time secret for PVE API token '#{tokenid}' in #{secret_file}")
  rescue SystemCallError => e
    raise Puppet::ResourceError,
          "PVE API token '#{tokenid}' WAS created, but its one-time secret could not be persisted to #{secret_file}: #{e.message}. " \
          'The secret is now lost; delete and recreate the token to obtain a new one.'
  end

  def tokens_for_user(context, userid)
    tokens = transport_get(context, "/access/users/#{userid}/token") || []
    tokens.map do |token|
      pve_to_puppet(token).merge(tokenid: "#{userid}!#{token['tokenid']}", ensure: 'present')
    end
  end

  def parse_tokenid!(tokenid)
    parts = tokenid.split('!')
    unless parts.length == 2 && parts[0].match?(%r{\A[^@\s]+@[^@\s]+\z}) && !parts[1].empty?
      raise Puppet::ResourceError,
            "tokenid must be in user@realm!tokenname format, got: #{tokenid.inspect}"
    end
    parts
  end
end
