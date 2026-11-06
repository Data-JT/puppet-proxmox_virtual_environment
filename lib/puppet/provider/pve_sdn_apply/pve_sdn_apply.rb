# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_sdn_apply resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveSdnApply::PveSdnApply < Puppet::Provider::PveSdnApply::ProxmoxVirtualEnvironment
end
