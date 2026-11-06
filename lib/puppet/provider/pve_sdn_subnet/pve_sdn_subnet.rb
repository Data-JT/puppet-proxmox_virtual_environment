# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_sdn_subnet resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveSdnSubnet::PveSdnSubnet < Puppet::Provider::PveSdnSubnet::ProxmoxVirtualEnvironment
end
