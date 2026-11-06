# frozen_string_literal: true

require_relative '../pve_sdn_base_provider'

# @api private
module Puppet::Provider::PveSdnVnet; end

# Provider for pve_sdn_vnet resources via the PVE REST API.
class Puppet::Provider::PveSdnVnet::ProxmoxVirtualEnvironment < Puppet::Provider::PveSdnBaseProvider
  def self.attribute_map
    {
      'vnet'          => :vnet,
      'type'          => :type,
      'zone'          => :zone,
      'tag'           => :vnet_tag,
      'alias'         => :vnet_alias,
      'vlanaware'     => :vlanaware,
      'isolate-ports' => :isolate_ports,
      'delete'        => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:vlanaware, :isolate_ports]
  end

  def self.sdn_collection_path
    '/cluster/sdn/vnets'
  end

  def self.sdn_id_key
    'vnet'
  end
end
