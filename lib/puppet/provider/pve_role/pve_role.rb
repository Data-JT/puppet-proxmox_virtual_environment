# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_role resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveRole::PveRole < Puppet::Provider::PveRole::ProxmoxVirtualEnvironment
end
