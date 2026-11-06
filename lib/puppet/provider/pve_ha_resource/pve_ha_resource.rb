# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_ha_resource resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveHaResource::PveHaResource < Puppet::Provider::PveHaResource::ProxmoxVirtualEnvironment
end
