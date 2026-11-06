# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_acl resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveAcl::PveAcl < Puppet::Provider::PveAcl::ProxmoxVirtualEnvironment
end
