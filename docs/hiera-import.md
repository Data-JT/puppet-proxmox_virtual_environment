# Importing an existing cluster into Hiera

How to adopt a PVE cluster that is already configured, by generating Hiera data from its live API.

`tools/pve_hiera_import.rb` generates Hiera data for the `proxmox_virtual_environment::resources`
class from the live PVE API, so Puppet can adopt resources that already exist. It is a
checkout-only utility and is intentionally not included in the Puppet Forge package. It verifies
TLS certificates by default; use `--no-ssl-verify` only on a trusted network when verification
cannot be configured.

## Running the import

First make sure the API token can read the resource types you want to import.

```sh
ruby tools/pve_hiera_import.rb \
  --host pve01.example.com \
  --token-id 'puppet@pve!puppet' \
  --token-secret-file /run/secrets/pve-token \
  --output pve-import.yaml
```

`--token-secret` is also accepted, but passing a secret on the command line exposes it in your
shell history and in process listings (`ps`). If the `proxmox_virtual_environment` class has
already written `<agent confdir>/pve_transport.yaml` (`/etc/puppetlabs/puppet` on AIO agents) on
the node, you can reuse that transport file instead:

```sh
ruby tools/pve_hiera_import.rb \
  --transport-config /etc/puppetlabs/puppet/pve_transport.yaml \
  --output pve-import.yaml
```

Run `ruby tools/pve_hiera_import.rb --help` for further options, such as `--skip-errors` and
`--include-transport-parameters`.

## Adopting the data

Add the generated data to the `cluster_manager` node's Hiera hierarchy and include
`proxmox_virtual_environment::resources` together with the main class. Run the first adoption pass
in no-op mode and review the proposed changes before applying normally:

```sh
puppet agent -t --noop
```

Existing PVE resources that are absent from the Hiera data are not purged by this module. Secrets
PVE does not return (storage and realm passwords, notification credentials, user passwords) are
not exported; add them encrypted, or leave the attribute out to keep the stored value unmanaged.
