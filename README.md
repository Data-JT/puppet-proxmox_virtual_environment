# datajt-proxmox_virtual_environment

Manage Proxmox Virtual Environment cluster configuration as Puppet code, through the PVE REST API.

## Table of contents

1. [Description](#description)
2. [Requirements](#requirements)
3. [Quick start](#quick-start)
4. [Resource types](#resource-types)
5. [Further documentation](#further-documentation)
6. [Limitations](#limitations)
7. [Contributing](#contributing)
8. [License](#license)

## Description

This module lets you describe the configuration of a [Proxmox Virtual Environment](https://www.proxmox.com/en/proxmox-virtual-environment/overview)
(PVE) cluster in Puppet code or Hiera: storage definitions, backup jobs, users, groups, roles,
permissions, authentication realms, notifications, pools, HA resources, datacenter and node
settings and software-defined networking. The Puppet agent on a PVE node compares that
description with the live configuration and changes only what differs.

### What it does

- Manages 21 kinds of PVE objects as native Puppet resource types (`pve_*`).
- Declares all of them from Hiera through one class, `proxmox_virtual_environment::resources`.
- Detects and enforces drift in secrets (storage and realm passwords, notification credentials,
  user passwords, SDN IPAM and DNS keys), and keeps them out of logs and reports.
- Restricts every write to one node of the cluster, named by `cluster_manager`, so a
  cluster-wide object is changed from exactly one catalog.
- Ships Bolt tasks for ad-hoc API calls and for applying SDN changes, and a
  checkout-only utility that imports an existing cluster into Hiera data.

### What it does not do

- It does not install PVE, manage its apt repository or its services. It configures an existing
  cluster.
- It does not manage guests: no VM or container definitions, no power operations.
- It does not use `puppet device`, a proxy agent or a Bolt transport. The agent runs on a PVE node.
- It does not purge PVE objects that are not declared in Puppet.
- It does not clear a value when you remove an attribute; use `delete_properties` for that.
- It does not apply SDN changes unless you declare `pve_sdn_apply`; writing SDN objects only
  stages them.
- It cannot verify API token secrets after creation: PVE keeps only a hash.
- It talks only to the REST API, with one exception: `pve_user` passwords are set with
  `pveum passwd` on the node, because PVE refuses token authentication for that endpoint.

### How it works

```text
Hiera / manifest ──> proxmox_virtual_environment class ──> pve_transport.yaml (token, 0600)
                                                                 │
Puppet agent on the PVE node ──> pve_* types ──> https://localhost:8006 (PVE REST API)
```

The `proxmox_virtual_environment` class writes the API token and connection settings to a
transport file in the agent's confdir. The `pve_*` types are built on the Puppet Resource API;
their providers read that file and call the local PVE API on every agent run. Resources come
from manifests or from Hiera via `proxmox_virtual_environment::resources`. Secrets PVE does not
return over the API are compared against PVE's own files under `/etc/pve/priv/`, which is why
the agent runs as root on the node.

## Requirements

- Puppet or OpenVox 8 or 9 (`>= 8.0.0 < 10.0.0`). Testing is currently done on 8 (CI and
  production); on 9 the unit tests pass (OpenVox 9.3), but there is no CI job or production
  use yet. No Forge dependencies; the Resource API ships with Puppet.
- Debian 12 (PVE 8.x) or Debian 13 (PVE 9.x). Tested against PVE 9.2.6.
- The Puppet agent running as root on a PVE node, with that node's certname set as
  `cluster_manager`.
- A PVE API token with the permissions for the objects you manage.

## Quick start

### 1. Prepare PVE

Create a dedicated user and a privilege-separated API token, then grant both the roles the
managed resource types need. The token's effective rights are the intersection of the two.
For example, to manage storage definitions only:

```sh
pveum user add puppet@pve
pveum user token add puppet@pve puppet --privsep 1      # prints the secret once
pveum acl modify /storage --users puppet@pve --roles PVEDatastoreAdmin
pveum acl modify /storage --tokens 'puppet@pve!puppet' --roles PVEDatastoreAdmin
```

Do not grant a blanket `Administrator` role on `/`. The
[permissions page](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/permissions.md)
lists the privileges each resource type needs.

### 2. Manifest

```puppet
# site/profile/manifests/pve.pp
class profile::pve {
  include proxmox_virtual_environment            # transport: token_id, token_secret, cluster_manager from Hiera
  include proxmox_virtual_environment::resources # pve_* resources from Hiera

  # Resources can also be declared directly:
  pve_pool { 'production':
    comment => 'Production guests',
  }
}
```

### 3. Hiera

```yaml
# Class parameters. Keep the secret encrypted (hiera-eyaml) and convert it to Sensitive.
lookup_options:
  proxmox_virtual_environment::token_secret:
    convert_to: Sensitive

proxmox_virtual_environment::token_id: 'puppet@pve!puppet'
proxmox_virtual_environment::token_secret: ENC[PKCS7,...]
proxmox_virtual_environment::cluster_manager: pve01.example.com   # certname of the writing node

# Resources
proxmox_virtual_environment::resources::storages:
  backup-nfs:
    type: nfs
    server: nfs.example.com
    nfs_export: /srv/pve-backups
    content: backup

proxmox_virtual_environment::resources::backup_jobs:
  nightly:
    enabled: true
    job_schedule: daily
    storage: backup-nfs
    mode: snapshot
    all: true
    prune_backups: 'keep-daily=7,keep-weekly=4'

proxmox_virtual_environment::resources::users:
  automation@pve:
    enable: true

proxmox_virtual_environment::resources::acls:
  '/|automation@pve|PVEAuditor':
    propagate: true

proxmox_virtual_environment::resources::ha_resources:
  'vm:114':
    state: started
    max_restart: 2
```

`ensure` defaults to `present`. The resources class orders related entries it declares itself
(realms and groups before users, users and roles before ACLs and tokens, storages and pools
before backup jobs, notification targets before matchers). Declare the class and the resources
on the `cluster_manager` node only; other nodes can read state but refuse to write. Run the
first pass with `puppet agent -t --noop`.

## Resource types

| Type | Manages |
|---|---|
| `pve_storage` | Storage definitions (NFS, CIFS, iSCSI, LVM, ZFS, Ceph, PBS, …) |
| `pve_backup_job` | Scheduled vzdump backup jobs and retention |
| `pve_user`, `pve_group`, `pve_role` | Users (including `@pve` passwords), groups, custom roles |
| `pve_api_token` | API tokens of a user |
| `pve_acl` | ACL entries (`path\|user-group-or-token\|role`) |
| `pve_realm` | LDAP, Active Directory and OpenID Connect realms |
| `pve_pool` | Resource pools |
| `pve_notification_target`, `pve_notification_matcher` | Notification endpoints and routing rules |
| `pve_ha_resource` | HA membership of a guest (`vm:` or `ct:` prefix) |
| `pve_datacenter_config`, `pve_node_config` | `datacenter.cfg` options and per-node settings |
| `pve_sdn_zone`, `pve_sdn_vnet`, `pve_sdn_subnet`, `pve_sdn_controller` | SDN objects (staged, not applied) |
| `pve_sdn_ipam`, `pve_sdn_dns` | SDN IPAM and DNS plugins (take effect immediately) |
| `pve_sdn_apply` | Applies pending SDN changes cluster-wide; opt-in |

Every attribute, the class parameters and the `pve_api_request` and `sdn_apply` tasks are
documented in [REFERENCE.md](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/REFERENCE.md).

## Further documentation

- [Class parameters and TLS](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/class-parameters.md): transport settings, `cluster_manager`, certificate verification, the transport file.
- [Token permissions](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/permissions.md): least-privilege roles and ACL paths per resource type.
- [Secret drift detection](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/secret-drift.md): how secrets are compared and redacted, and why user passwords use `pveum`.
- [Clearing optional properties](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/clearing-properties.md): removing a value on the PVE side with `delete_properties`.
- [Software-defined networking](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/sdn.md): pending versus applied state, `pve_sdn_apply`, subnet identity, the SDN lock.
- [High availability](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/ha.md): what `pve_ha_resource` manages and what it leaves alone.
- [API tokens](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/api-tokens.md): keeping the one-time secret with `secret_file`.
- [Resource notes](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/resource-notes.md): per-type behaviour (immutable types, backup job guest lists, webhooks, singletons, groups, roles).
- [Importing an existing cluster](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/hiera-import.md): generate Hiera data from a live PVE.
- [Ad-hoc API access](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/docs/api-access.md): the `pve_api_request` Bolt task.

## Limitations

- Managing any secret stored under `/etc/pve/priv`, and `pve_user` passwords, requires the agent
  on the PVE node as root. If a secret's store cannot be read, the run fails rather than
  reporting the resource in sync.
- Provider writes are restricted to the `cluster_manager` node; other nodes fail closed on
  create, update and delete.
- SDN changes are staged only; applying them requires `pve_sdn_apply`, which reloads networking
  on every node. SDN fabrics, prefix lists, route maps and rollback are not modelled.
- The `type` of a storage, realm or notification target cannot be changed; remove and re-create it.
- `pve_node_config` and `pve_datacenter_config` cannot be deleted; `ensure => absent` fails.
- `pve_role` manages custom roles only; `pve_group` does not manage membership (set it through
  `pve_user`).

## Contributing

Issues and pull requests are welcome on
[GitHub](https://github.com/Data-JT/puppet-proxmox_virtual_environment/issues); please open an
issue before significant work. See [CONTRIBUTING.md](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/CONTRIBUTING.md)
for the development workflow and [SECURITY.md](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/SECURITY.md)
for reporting vulnerabilities.

## License

Apache-2.0, see [LICENSE](https://github.com/Data-JT/puppet-proxmox_virtual_environment/blob/master/LICENSE).
