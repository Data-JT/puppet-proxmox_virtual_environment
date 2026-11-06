# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_pool resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PvePool::PvePool < Puppet::Provider::PvePool::ProxmoxVirtualEnvironment
end
