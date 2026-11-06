# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_api_token resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveApiToken::PveApiToken < Puppet::Provider::PveApiToken::ProxmoxVirtualEnvironment
end
