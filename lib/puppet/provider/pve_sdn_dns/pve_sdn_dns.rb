# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_sdn_dns resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveSdnDns::PveSdnDns < Puppet::Provider::PveSdnDns::ProxmoxVirtualEnvironment
end
