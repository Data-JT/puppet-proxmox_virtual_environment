# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_node_config resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveNodeConfig::PveNodeConfig < Puppet::Provider::PveNodeConfig::ProxmoxVirtualEnvironment
end
