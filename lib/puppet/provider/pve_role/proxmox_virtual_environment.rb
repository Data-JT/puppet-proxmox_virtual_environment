# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveRole; end

# Provider for pve_role resources via the PVE REST API.
#
# PVE stores privileges as a comma-separated 'pve-priv-list' string; the type
# exposes them as an Array[String] for easier declaration in Puppet/Hiera.
class Puppet::Provider::PveRole::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'roleid' => :roleid,
      'privs'  => :privs,
    }
  end

  # PVE returns a role's privilege list in its own canonical order regardless of
  # the order it was declared or sent in; compare privs as an unordered set so
  # runs converge instead of re-sending the declared order every time.
  def insync?(context, name, attribute_name, is, should)
    return Array(is[:privs]).sort == Array(should[:privs]).sort if attribute_name == :privs

    super
  end

  def get(context)
    (transport_get(context, '/access/roles') || []).filter_map do |role|
      next if to_bool(role['special'])

      {
        roleid: role['roleid'],
        privs:  privs_to_array(role['privs']),
        ensure: 'present',
      }
    end
  end

  def create(context, name, should)
    context.notice("Creating role '#{name}'")
    pve_transport(context).post(context, '/access/roles', { 'roleid' => name, 'privs' => privs_to_string(should[:privs]) })
  end

  def update(context, name, should)
    context.notice("Updating role '#{name}'")
    pve_transport(context).put(context, "/access/roles/#{name}", { 'privs' => privs_to_string(should[:privs]) })
  end

  def delete(context, name)
    context.notice("Deleting role '#{name}'")
    pve_transport(context).delete(context, "/access/roles/#{name}")
  end

  private

  def privs_to_array(value)
    return [] if value.nil? || value.empty?

    value.split(',')
  end

  def privs_to_string(value)
    Array(value).join(',')
  end
end
