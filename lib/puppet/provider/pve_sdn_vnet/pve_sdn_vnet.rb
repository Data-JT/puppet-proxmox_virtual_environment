# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_sdn_vnet resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveSdnVnet::PveSdnVnet < Puppet::Provider::PveSdnVnet::ProxmoxVirtualEnvironment
end
