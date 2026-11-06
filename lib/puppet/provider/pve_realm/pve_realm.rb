# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_realm resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveRealm::PveRealm < Puppet::Provider::PveRealm::ProxmoxVirtualEnvironment
end
