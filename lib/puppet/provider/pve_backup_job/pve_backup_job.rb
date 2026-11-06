# frozen_string_literal: true

require_relative 'proxmox_virtual_environment'

# Default provider for pve_backup_job resources. Delegates to ProxmoxVirtualEnvironment.
class Puppet::Provider::PveBackupJob::PveBackupJob < Puppet::Provider::PveBackupJob::ProxmoxVirtualEnvironment
end
