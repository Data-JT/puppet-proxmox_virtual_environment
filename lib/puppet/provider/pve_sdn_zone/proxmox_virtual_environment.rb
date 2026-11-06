# frozen_string_literal: true

require_relative '../pve_sdn_base_provider'

# @api private
module Puppet::Provider::PveSdnZone; end

# Provider for pve_sdn_zone resources via the PVE REST API.
class Puppet::Provider::PveSdnZone::ProxmoxVirtualEnvironment < Puppet::Provider::PveSdnBaseProvider
  # Attributes PVE accepts only for particular zone plugin types. Declaring one
  # on a zone of another type can never converge -- PVE rejects the request as
  # an unexpected parameter -- so it is reported as a configuration error rather
  # than left as a perpetual no-op diff. This mirrors pve_storage's
  # settable_should.
  PLUGIN_ONLY_ATTRIBUTES = {
    bridge:                      ['vlan', 'qinq'],
    service_vlan:                ['qinq'],
    vlan_protocol:               ['qinq'],
    peers:                       ['vxlan', 'evpn'],
    vxlan_port:                  ['vxlan', 'evpn'],
    fabric:                      ['vxlan', 'evpn'],
    controller:                  ['evpn'],
    secondary_controllers:       ['evpn'],
    vrf_vxlan:                   ['evpn'],
    exitnodes:                   ['evpn'],
    exitnodes_local_routing:     ['evpn'],
    exitnodes_primary:           ['evpn'],
    advertise_subnets:           ['evpn'],
    disable_arp_nd_suppression:  ['evpn'],
    rt_import:                   ['evpn'],
    mac:                         ['evpn'],
    bridge_disable_mac_learning: ['qinq', 'vxlan', 'evpn'],
    dp_id:                       ['faucet'],
  }.freeze

  def self.attribute_map
    {
      'zone'                        => :zone,
      'type'                        => :type,
      'nodes'                       => :nodes,
      'mtu'                         => :mtu,
      'ipam'                        => :ipam,
      'dns'                         => :dns,
      'reversedns'                  => :reversedns,
      'dnszone'                     => :dnszone,
      'dhcp'                        => :dhcp,
      'bridge'                      => :bridge,
      'tag'                         => :service_vlan,
      'vlan-protocol'               => :vlan_protocol,
      'peers'                       => :peers,
      'vxlan-port'                  => :vxlan_port,
      'fabric'                      => :fabric,
      'controller'                  => :controller,
      'secondary-controllers'       => :secondary_controllers,
      'vrf-vxlan'                   => :vrf_vxlan,
      'exitnodes'                   => :exitnodes,
      'exitnodes-local-routing'     => :exitnodes_local_routing,
      'exitnodes-primary'           => :exitnodes_primary,
      'advertise-subnets'           => :advertise_subnets,
      'disable-arp-nd-suppression'  => :disable_arp_nd_suppression,
      'rt-import'                   => :rt_import,
      'mac'                         => :mac,
      'bridge-disable-mac-learning' => :bridge_disable_mac_learning,
      'dp-id'                       => :dp_id,
      'delete'                      => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:exitnodes_local_routing, :advertise_subnets, :disable_arp_nd_suppression, :bridge_disable_mac_learning]
  end

  # PVE renders these back in its own order, so a raw string compare would
  # re-PUT an identical value on every run.
  def self.unordered_csv_attributes
    [:nodes, :peers, :exitnodes, :rt_import]
  end

  def self.string_list_attributes
    [:secondary_controllers]
  end

  def self.sdn_collection_path
    '/cluster/sdn/zones'
  end

  def self.sdn_id_key
    'zone'
  end

  def create(context, name, should)
    super(context, name, checked_should(should))
  end

  def update(context, name, should)
    super(context, name, checked_should(should))
  end

  private

  # Returns should unchanged, or raises when it names an attribute PVE would
  # reject outright for the declared plugin type.
  def checked_should(should)
    misplaced = misplaced_attributes(should)
    return should if misplaced.empty?

    raise Puppet::ResourceError,
          "SDN zone type '#{should[:type]}' does not accept: #{misplaced.join(', ')}"
  end

  def misplaced_attributes(should)
    type = should[:type].to_s
    PLUGIN_ONLY_ATTRIBUTES.filter_map do |attribute, types|
      "#{attribute} (#{types.join(', ')} only)" if should[attribute] && !types.include?(type)
    end
  end
end
