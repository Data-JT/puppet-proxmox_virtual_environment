# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_sdn_controller resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveSdnController::PveSdnController < Puppet::Provider::PveSdnController::ProxmoxVirtualEnvironment
end
