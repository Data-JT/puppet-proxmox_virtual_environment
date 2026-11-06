# frozen_string_literal: true

# require_relative, not require: a module's lib/ is on the load path on agents
# (pluginsync copies it into $libdir) but NOT inside puppetserver, which loads
# type files through Puppet's autoloader by absolute path without extending
# $LOAD_PATH. A bare require therefore raises LoadError during catalog
# compilation -- see the note in puppet_x/proxmox_virtual_environment/config.rb.
require_relative '../../puppet_x/proxmox_virtual_environment/config'

# Registers the managed PVE transport file as an automatic dependency.
module Puppet::Type::PveTransportAutorequire
  def self.register(type_name)
    Puppet::Type.type(type_name).autorequire(:file) do
      File.join(Puppet.settings[:confdir], PuppetX::ProxmoxVirtualEnvironment::CONFIG_FILENAME)
    end
  end
end
