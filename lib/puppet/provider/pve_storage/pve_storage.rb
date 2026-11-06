# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_storage resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveStorage::PveStorage < Puppet::Provider::PveStorage::ProxmoxVirtualEnvironment
end
