# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveNodeConfig; end

# Provider for pve_node_config resources via the PVE REST API.
#
# Maps to GET/PUT /nodes/{node}/config. get() discovers all nodes through
# /nodes. PVE node config objects cannot be deleted.
class Puppet::Provider::PveNodeConfig::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'description'       => :description,
      'location'          => :location,
      'wakeonlan'         => :wakeonlan,
      'startall-onboot-delay' => :startall_onboot_delay,
      'ballooning-target' => :ballooning_target,
      'delete'            => :delete_properties,
    }
  end

  def self.boolean_attributes
    []
  end

  def get(context)
    (transport_get(context, '/nodes') || []).filter_map do |node|
      node_name = node['node']
      next unless node_name

      node_config(context, node_name)
    end
  end

  def create(context, name, should)
    # Node config always exists; create is identical to update.
    update(context, name, should)
  end

  def update(context, name, should)
    context.notice("Updating node config for '#{name}'")
    pve_transport(context).put(context, "/nodes/#{name}/config", update_body(context, should))
  end

  def delete(_context, name)
    raise Puppet::ResourceError, "pve_node_config '#{name}' cannot be deleted"
  end

  private

  # A single unreachable node (e.g. powered off) must not abort discovery for
  # every other node. transport_get already swallows the missing-transport-config
  # case; this rescue is only for API errors from a reachable config but offline
  # node. Returning nil drops the node from the filter_map result.
  def node_config(context, node_name)
    config = transport_get(context, "/nodes/#{node_name}/config") || {}
    result = pve_to_puppet(config).merge(ensure: 'present', node: node_name)
    description = result[:description]
    result[:description] = description.chomp if description.is_a?(String)
    result
  rescue Puppet::ResourceError => e
    context.warning("Skipping PVE node '#{node_name}': #{e.message}")
    nil
  end
end
