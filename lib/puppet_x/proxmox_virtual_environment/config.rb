# frozen_string_literal: true

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxVirtualEnvironment; end

# Shared constants for the proxmox_virtual_environment module. Kept
# dependency-light because it is required from a type helper that loads on
# both server and agent at type-load time.
#
# ALWAYS require this file with `require_relative`, never
# `require 'puppet_x/proxmox_virtual_environment/config'`.
#
# The bare form works on agents and in a plain-Ruby `puppet catalog compile`,
# because pluginsync copies module lib/ content into $libdir, which is on
# $LOAD_PATH. It does NOT work inside puppetserver: there, type files are loaded
# by Puppet's autoloader from an absolute path in the environment's modulepath,
# and module lib/ directories are never added to $LOAD_PATH. The bare require
# then raises LoadError while the type is being autoloaded, and every catalog
# declaring a pve_* resource fails to compile with:
#
#   Could not autoload puppet/type/pve_storage:
#   no such file to load -- puppet_x/proxmox_virtual_environment/config
#
# That failure hid for a long time: a long-running puppetserver keeps the class
# cached once loaded, so the breakage only appears after a restart -- and then
# looks like whatever was deployed most recently. Verified 2026-08-05 by
# reproducing it on the previous release as well.
module PuppetX::ProxmoxVirtualEnvironment
  # Filename (relative to Puppet's confdir) of the managed transport config.
  CONFIG_FILENAME = 'pve_transport.yaml'
end
