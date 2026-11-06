# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_group resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveGroup::PveGroup < Puppet::Provider::PveGroup::ProxmoxVirtualEnvironment
end
