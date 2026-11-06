# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_user resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveUser::PveUser < Puppet::Provider::PveUser::ProxmoxVirtualEnvironment
end
