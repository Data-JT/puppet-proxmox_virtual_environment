# frozen_string_literal: true

require_relative '../pve_sdn_base_provider'

# @api private
module Puppet::Provider::PveSdnController; end

# Provider for pve_sdn_controller resources via the PVE REST API.
class Puppet::Provider::PveSdnController::ProxmoxVirtualEnvironment < Puppet::Provider::PveSdnBaseProvider
  def self.attribute_map
    {
      'controller'                  => :controller,
      'type'                        => :type,
      'asn'                         => :asn,
      'peers'                       => :peers,
      'fabric'                      => :fabric,
      'peer-group-name'             => :peer_group_name,
      'node'                        => :node,
      'ebgp'                        => :ebgp,
      'ebgp-multihop'               => :ebgp_multihop,
      'bgp-mode'                    => :bgp_mode,
      'bgp-multipath-as-path-relax' => :bgp_multipath_as_path_relax,
      'loopback'                    => :loopback,
      'route-map-in'                => :route_map_in,
      'route-map-out'               => :route_map_out,
      'isis-domain'                 => :isis_domain,
      'isis-ifaces'                 => :isis_ifaces,
      'isis-net'                    => :isis_net,
      'nodes'                       => :nodes,
      'delete'                      => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:ebgp, :bgp_multipath_as_path_relax]
  end

  def self.unordered_csv_attributes
    [:peers, :isis_ifaces, :nodes]
  end

  def self.sdn_collection_path
    '/cluster/sdn/controllers'
  end

  def self.sdn_id_key
    'controller'
  end
end
