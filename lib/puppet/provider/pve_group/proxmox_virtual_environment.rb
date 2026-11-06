# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveGroup; end

# Provider for pve_group resources via the PVE REST API.
#
# GET /access/groups returns a 'users' string (the index call) while
# GET /access/groups/{groupid} returns a 'members' array; both are exposed
# read-only through the members attribute. Membership itself is managed via
# pve_user's groups attribute or external realm sync, not here.
class Puppet::Provider::PveGroup::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'groupid' => :groupid,
      'comment' => :comment,
    }
  end

  def get(context)
    (transport_get(context, '/access/groups') || []).map do |group|
      members = group['users'].to_s.split(',').reject(&:empty?)
      pve_to_puppet(group).merge(ensure: 'present', members: members)
    end
  end

  def create(context, name, should)
    context.notice("Creating group '#{name}'")
    pve_transport(context).post(context, '/access/groups', create_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating group '#{name}'")
    pve_transport(context).put(context, "/access/groups/#{name}", update_body(context, should))
  end

  def delete(context, name)
    context.notice("Deleting group '#{name}'")
    pve_transport(context).delete(context, "/access/groups/#{name}")
  end
end
