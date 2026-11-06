# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_notification_matcher resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveNotificationMatcher::PveNotificationMatcher < Puppet::Provider::PveNotificationMatcher::ProxmoxVirtualEnvironment
end
