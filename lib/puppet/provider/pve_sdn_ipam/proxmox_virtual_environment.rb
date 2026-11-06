# frozen_string_literal: true

require_relative '../pve_sdn_base_provider'

# @api private
module Puppet::Provider::PveSdnIpam; end

# Provider for pve_sdn_ipam resources via the PVE REST API.
class Puppet::Provider::PveSdnIpam::ProxmoxVirtualEnvironment < Puppet::Provider::PveSdnBaseProvider
  def self.attribute_map
    {
      'ipam'        => :ipam,
      'type'        => :type,
      'url'         => :url,
      'token'       => :token,
      'section'     => :section,
      'fingerprint' => :fingerprint,
      'delete'      => :delete_properties,
    }
  end

  # ipams have no pending/running split: the index endpoint accepts neither
  # flag and .running-config carries no ipams section, because PVE queries the
  # backend live rather than rendering it into the network configuration.
  def self.pending_aware?
    false
  end

  def self.sdn_collection_path
    '/cluster/sdn/ipams'
  end

  def self.sdn_id_key
    'ipam'
  end
end
