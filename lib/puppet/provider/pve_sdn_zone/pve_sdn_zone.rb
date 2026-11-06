# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_sdn_zone resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveSdnZone::PveSdnZone < Puppet::Provider::PveSdnZone::ProxmoxVirtualEnvironment
end
