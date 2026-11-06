# Class parameters and TLS

The `proxmox_virtual_environment` class configures how the providers reach the PVE API and which
node may write. The generated parameter reference is in
[REFERENCE.md](../REFERENCE.md#proxmox_virtual_environment); this page adds the context around it.

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `token_id` | `Pattern[/\A[^@!\s]+@[^@!\s]+![^!\s]+\z/]` | — | API token ID (`user@realm!tokenname`) |
| `token_secret` | `Sensitive[String]` | — | API token secret |
| `cluster_manager` | `String` | — | Puppet certname of the only node permitted to make PVE API changes |
| `host` | `String` | `'localhost'` | PVE hostname or IP |
| `port` | `Integer` | `8006` | PVE API port |
| `ssl_verify` | `Boolean` | `true` | Verify the PVE TLS certificate |
| `ssl_ca_file` | `Optional[Pattern[/\A\//]]` (absolute path) | `'/etc/pve/pve-root-ca.pem'` | CA bundle path (when `ssl_verify` is `true`); `undef` omits it |
| `config_file` | `Pattern[/\A\//]` (absolute path) | `<agent confdir>/pve_transport.yaml` | Where to write the transport credentials |

`token_secret` must be `Sensitive`. When it comes from Hiera, convert it with `lookup_options`:

```yaml
lookup_options:
  proxmox_virtual_environment::token_secret:
    convert_to: Sensitive
```

In a manifest, wrap it explicitly:

```puppet
class { 'proxmox_virtual_environment':
  token_id        => 'puppet@pve!puppet',
  token_secret    => Sensitive(lookup('pve::token_secret')),
  cluster_manager => 'pve01.example.com',
}
```

## The cluster manager

All provider writes are restricted to the Puppet certname configured as `cluster_manager`. State
discovery remains available everywhere, but create, update and delete operations fail closed on
any other node, or when `cluster_manager` is missing. Declare cluster-wide resources only in the
manager node's catalog; declaring them on every node would make each node race to write the same
shared `/etc/pve` configuration.

## TLS verification

TLS certificates are verified by default against the cluster CA at `/etc/pve/pve-root-ca.pem`,
which signs the certificate PVE serves on `localhost`. Set `ssl_ca_file` to another CA bundle
when connecting to a remote host or when PVE uses a custom certificate, or set it to `undef` to
use the system trust store. Disabling verification (`ssl_verify => false`) allows
man-in-the-middle attacks on the API connection; it is only a reasonable trade-off when the API
traffic never leaves the node (`host => 'localhost'`, the default).

## The transport file

The class writes the credentials to `config_file` (mode `0600`, `root:root`), which the providers
read at agent run time. Declare the class on every PVE node that runs `pve_*` resources, in
`site.pp`, a role or a profile.

- All `pve_*` types automatically require the managed transport file when it is present in the
  catalog. On a first run, providers wait for that file and refresh actual PVE state before
  creating or updating resources, so a single `puppet agent -t` applies the class and all
  `pve_*` resources in the same pass. Credentials are reloaded when the file changes.
- When `config_file` points elsewhere, the class creates a symlink at the provider discovery path
  (`<agent confdir>/pve_transport.yaml`).
- The default is the agent's own confdir (from the `proxmox_virtual_environment_confdir` fact),
  not the compiling server's, since the two can differ.
