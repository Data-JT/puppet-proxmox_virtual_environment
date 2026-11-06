# frozen_string_literal: true

require_relative '../pve_sdn_base_provider'

# @api private
module Puppet::Provider::PveSdnSubnet; end

# Provider for pve_sdn_subnet resources via the PVE REST API.
#
# Subnets are the only nested SDN object class, and the only one whose PVE
# identifier is derived rather than declared. PVE/API2/Network/SDN/Subnets.pm
# builds it as "<zone>-<cidr with / replaced by ->", where the zone comes from
# the VNet, and then addresses the object by that identifier on update and
# delete. Only create accepts a bare CIDR.
class Puppet::Provider::PveSdnSubnet::ProxmoxVirtualEnvironment < Puppet::Provider::PveSdnBaseProvider
  VNETS_PATH = '/cluster/sdn/vnets'
  VNET_PATH = '/cluster/sdn/vnets/{vnet}'
  SUBNETS_PATH = '/cluster/sdn/vnets/{vnet}/subnets'
  SUBNET_PATH = '/cluster/sdn/vnets/{vnet}/subnets/{subnet}'

  def self.attribute_map
    {
      'vnet'            => :vnet,
      'type'            => :type,
      'gateway'         => :gateway,
      'snat'            => :snat,
      'dnszoneprefix'   => :dnszoneprefix,
      'dhcp-range'      => :dhcp_range,
      'dhcp-dns-server' => :dhcp_dns_server,
      'delete'          => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:snat]
  end

  def self.property_string_array_attributes
    [:dhcp_range]
  end

  def self.sdn_id_key
    'subnet'
  end

  def self.sdn_object_label
    'subnet'
  end

  def initialize
    super
    @subnet_ids = {}
    @zone_by_vnet = {}
  end

  def get(context)
    vnet_names(context).flat_map { |vnet| subnets_in(context, vnet) }
  end

  def create(context, name, should)
    vnet = name[:vnet]
    cidr = name[:cidr]
    context.notice("Creating SDN subnet '#{cidr}' in VNet '#{vnet}' (pending; not applied)")
    body = create_body(context, should).merge('subnet' => cidr, 'type' => 'subnet')
    sdn_call(context, 'POST', SUBNETS_PATH, body: body, path_params: { vnet: vnet })
  end

  def update(context, name, should)
    context.notice("Updating SDN subnet '#{name[:cidr]}' in VNet '#{name[:vnet]}' (pending; not applied)")
    sdn_call(context, 'PUT', SUBNET_PATH,
             body: update_body(context, mutable_should(context, should)),
             path_params: subnet_path_params(context, name))
  end

  def delete(context, name)
    context.notice("Deleting SDN subnet '#{name[:cidr]}' in VNet '#{name[:vnet]}' (pending; not applied)")
    sdn_call(context, 'DELETE', SUBNET_PATH, path_params: subnet_path_params(context, name))
  end

  private

  def vnet_names(context)
    Array(transport_get(context, VNETS_PATH)).filter_map do |entry|
      vnet = entry['vnet']
      @zone_by_vnet[vnet] = entry['zone'] if vnet
      vnet
    end
  end

  def subnets_in(context, vnet)
    states = subnet_pending_states(context, vnet)
    Array(transport_get(context, subnets_path(vnet))).map { |entry| to_subnet(entry, vnet, states) }
  end

  def to_subnet(entry, vnet, states)
    id = entry[self.class.sdn_id_key].to_s
    cidr = cidr_from_id(id)
    @subnet_ids[[vnet, cidr]] = id
    with_pending_state(pve_to_puppet(entry).merge(ensure: 'present', vnet: vnet, cidr: cidr, subnet_id: id), states[id])
  end

  def with_pending_state(hash, state)
    hash[:pending_state] = state if state
    hash
  end

  def subnet_pending_states(context, vnet)
    collect_pending_states(transport_get(context, subnets_path(vnet), 'pending' => 1))
  end

  # VNet identifiers are limited to eight alphanumeric characters, so plain
  # interpolation is safe here; mutations go through the transport's
  # expand_path, which escapes.
  def subnets_path(vnet)
    "#{VNETS_PATH}/#{vnet}/subnets"
  end

  # Mirrors parse_sdn_subnet_id in PVE/Network/SDN/SubnetPlugin.pm, which splits
  # the identifier on dashes into zone, address and prefix length. Zone
  # identifiers are alphanumeric, and IPv6 addresses use colons, so neither
  # introduces an extra dash.
  def cidr_from_id(id)
    _zone, address, prefix = id.split('-')
    prefix ? "#{address}/#{prefix}" : id
  end

  def subnet_path_params(context, name)
    { vnet: name[:vnet], subnet: subnet_id(context, name) }
  end

  # Cached from discovery. The fallback covers a resource PVE returned no entry
  # for, and derives the identifier the same way PVE does.
  def subnet_id(context, name)
    vnet = name[:vnet]
    cidr = name[:cidr]
    @subnet_ids[[vnet, cidr]] ||= "#{zone_for(context, vnet)}-#{cidr.tr('/', '-')}"
  end

  def zone_for(context, vnet)
    @zone_by_vnet[vnet] ||= fetch_zone(context, vnet)
  end

  def fetch_zone(context, vnet)
    entry = pve_transport(context).call(context, 'GET', VNET_PATH, path_params: { vnet: vnet })
    zone = entry.is_a?(Hash) ? entry['zone'] : nil
    raise Puppet::ResourceError, "Cannot determine the zone of SDN VNet '#{vnet}'" unless zone

    zone
  end
end
