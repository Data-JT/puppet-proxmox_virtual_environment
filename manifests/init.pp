# @summary Configures the PVE transport credentials on the node running the Puppet agent.
#
# Writes a YAML file that the proxmox_virtual_environment providers read at runtime
# to authenticate against the local PVE REST API. Declare this class on every
# PVE node before declaring any pve_* resources.
#
# @param token_id
#   API token ID (format: user@realm!tokenname, e.g. root@pam!puppet).
# @param token_secret
#   API token secret. Wrapped in Sensitive; never written to Puppet reports.
# @param cluster_manager
#   Puppet certname of the only node permitted to make PVE API changes.
# @param host
#   PVE hostname or IP. Defaults to localhost (the PVE API on the same node).
# @param port
#   PVE API port. Defaults to 8006.
# @param ssl_verify
#   Whether to verify the PVE TLS certificate. Defaults to true.
# @param ssl_ca_file
#   Path to a CA certificate file when ssl_verify is true and PVE uses a private CA.
#   Passing undef explicitly disables the private-CA default and omits ssl_ca_file
#   from the rendered transport config.
# @param config_file
#   Absolute path where the transport config YAML is written.
#   A symlink is created at the provider discovery path when this differs.
#   Defaults to the agent's own confdir (fact `proxmox_virtual_environment_confdir`), which is where
#   the providers look; the compiling server's confdir may differ.
# @example Configure providers to use the local PVE API
#   class { 'proxmox_virtual_environment':
#     token_id        => 'puppet@pve!puppet',
#     token_secret    => Sensitive(lookup('pve::token_secret')),
#     cluster_manager => 'pve01.example.com',
#   }
class proxmox_virtual_environment (
  Pattern[/\A[^@!\s]+@[^@!\s]+![^!\s]+\z/] $token_id,
  Sensitive[String]                        $token_secret,
  String                                   $cluster_manager,
  String                                   $host        = 'localhost',
  Integer                                  $port        = 8006,
  Boolean                                  $ssl_verify  = true,
  Optional[Pattern[/\A\//]]                $ssl_ca_file = '/etc/pve/pve-root-ca.pem', # lint:ignore:optional_default
  # The agent's confdir, from the proxmox_virtual_environment_confdir fact: the
  # providers read Puppet.settings[:confdir] on the node, while
  # $settings::confdir here is the COMPILING server's, which differs when
  # server and agent use different layouts (AIO server, Debian agent).
  # $settings::confdir only before the fact has been pluginsynced.
  Pattern[/\A\//]                          $config_file = "${$facts['proxmox_virtual_environment_confdir'].lest || { $settings::confdir }}/pve_transport.yaml",
) {
  file { $config_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => Sensitive(epp('proxmox_virtual_environment/pve_transport.epp', {
          'host'            => $host,
          'port'            => $port,
          'token_id'        => $token_id,
          'token_secret'    => $token_secret.unwrap,
          'cluster_manager' => $cluster_manager,
          'ssl_verify'      => $ssl_verify,
          'ssl_ca_file'     => $ssl_ca_file,
    })),
  }

  # Providers always read the fixed discovery path, so a relocated config is
  # linked back to it.
  $provider_config_file = "${$facts['proxmox_virtual_environment_confdir'].lest || { $settings::confdir }}/pve_transport.yaml"
  if $config_file != $provider_config_file {
    file { $provider_config_file:
      ensure  => link,
      target  => $config_file,
      require => File[$config_file],
    }
  }
}
