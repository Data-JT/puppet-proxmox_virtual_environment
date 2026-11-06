# frozen_string_literal: true

require_relative '../pve_sdn_base_provider'

# @api private
module Puppet::Provider::PveSdnDns; end

# Provider for pve_sdn_dns resources via the PVE REST API.
class Puppet::Provider::PveSdnDns::ProxmoxVirtualEnvironment < Puppet::Provider::PveSdnBaseProvider
  def self.attribute_map
    {
      'dns'           => :dns,
      'type'          => :type,
      'url'           => :url,
      'key'           => :key,
      'ttl'           => :ttl,
      'reversemaskv6' => :reversemaskv6,
      'fingerprint'   => :fingerprint,
      'delete'        => :delete_properties,
    }
  end

  # dns backends have no pending/running split: the index endpoint accepts
  # neither flag and .running-config carries no dns section, because PVE calls
  # the backend live rather than rendering it into the network configuration.
  def self.pending_aware?
    false
  end

  def self.sdn_collection_path
    '/cluster/sdn/dns'
  end

  def self.sdn_id_key
    'dns'
  end
end
