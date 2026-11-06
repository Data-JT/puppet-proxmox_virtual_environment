# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_sdn_ipam resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveSdnIpam::PveSdnIpam < Puppet::Provider::PveSdnIpam::ProxmoxVirtualEnvironment
end
