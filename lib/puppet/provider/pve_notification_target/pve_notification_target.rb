# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_notification_target resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveNotificationTarget::PveNotificationTarget < Puppet::Provider::PveNotificationTarget::ProxmoxVirtualEnvironment
end
