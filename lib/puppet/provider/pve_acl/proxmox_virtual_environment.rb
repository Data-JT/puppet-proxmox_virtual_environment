# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveAcl; end

# Provider for pve_acl resources via the PVE REST API.
class Puppet::Provider::PveAcl::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'path'      => :acl_path,
      'ugid'      => :ugid,
      'roleid'    => :role, # PVE >= 2.x returns 'roleid'; 'role' below is a fallback for older API responses
      'role'      => :role,
      'propagate' => :propagate,
    }
  end

  def self.boolean_attributes
    [:propagate]
  end

  def get(context)
    (transport_get(context, '/access/acl') || []).map do |entry|
      attrs = pve_to_puppet(entry).merge(ensure: 'present')
      # PVE returns group principals as bare names with type 'group'; the
      # canonical Puppet form prefixes them with '@' (matching user.cfg syntax).
      if entry['type'] == 'group' && !attrs[:ugid].to_s.start_with?('@')
        attrs[:ugid] = "@#{attrs[:ugid]}"
      end
      attrs.merge(title: "#{attrs[:acl_path]}|#{attrs[:ugid]}|#{attrs[:role]}")
    end
  end

  def create(context, name, should)
    context.notice("Creating ACL '#{name}'")
    pve_transport(context).put(context, '/access/acl', acl_body(should))
  end

  def update(context, name, should)
    context.notice("Updating ACL '#{name}'")
    pve_transport(context).put(context, '/access/acl', acl_body(should))
  end

  # name is a namevar hash (e.g. { acl_path: '/', ugid: 'user@pve', role: 'PVEAdmin' }), not a
  # plain string. Resource API passes a hash for resources with multiple namevars.
  def delete(context, name)
    context.notice("Deleting ACL '#{name}'")
    pve_transport(context).put(context, '/access/acl', acl_body(name).merge('delete' => true))
  end

  private

  # Builds the PUT /access/acl request body from a `should` hash (create/update)
  # or a namevar hash (delete). The propagate key is omitted when absent so that
  # delete requests only carry the identifying fields plus delete: true.
  def acl_body(attrs)
    body = { 'path' => attrs[:acl_path], 'roles' => attrs[:role] }
    principal = attrs[:ugid]
    if principal.start_with?('@')
      # PVE's PUT /access/acl expects bare group names and rejects the '@' prefix.
      body['groups'] = principal.sub(%r{\A@}, '')
    elsif principal.include?('!')
      body['tokens'] = principal
    else
      body['users'] = principal
    end
    body['propagate'] = to_bool(attrs[:propagate]) if attrs.key?(:propagate)
    body
  end
end
