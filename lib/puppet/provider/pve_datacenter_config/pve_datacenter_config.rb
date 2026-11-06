# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_datacenter_config resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveDatacenterConfig::PveDatacenterConfig < Puppet::Provider::PveDatacenterConfig::ProxmoxVirtualEnvironment
end
