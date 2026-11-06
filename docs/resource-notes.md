# Resource notes

Behaviour of individual `pve_*` types that is not obvious from their attribute lists. The
attributes themselves are documented in [REFERENCE.md](../REFERENCE.md).

## Resource types and API endpoints

| Type | API endpoint |
|---|---|
| `pve_storage` | `/storage` |
| `pve_backup_job` | `/cluster/backup` |
| `pve_user` | `/access/users` |
| `pve_api_token` | `/access/users/{userid}/token/{tokenid}` |
| `pve_acl` | `/access/acl` |
| `pve_realm` | `/access/domains` |
| `pve_node_config` | `/nodes/{node}/config` |
| `pve_notification_target` | `/cluster/notifications/endpoints/{type}` |
| `pve_notification_matcher` | `/cluster/notifications/matchers` |
| `pve_pool` | `/pools` |
| `pve_role` | `/access/roles` |
| `pve_group` | `/access/groups` |
| `pve_datacenter_config` | `/cluster/options` |
| `pve_ha_resource` | `/cluster/ha/resources` |
| `pve_sdn_zone` | `/cluster/sdn/zones` |
| `pve_sdn_vnet` | `/cluster/sdn/vnets` |
| `pve_sdn_subnet` | `/cluster/sdn/vnets/{vnet}/subnets` |
| `pve_sdn_controller` | `/cluster/sdn/controllers` |
| `pve_sdn_ipam` | `/cluster/sdn/ipams` |
| `pve_sdn_dns` | `/cluster/sdn/dns` |
| `pve_sdn_apply` | `/cluster/sdn` (apply) |

The implementation follows the official [PVE API viewer](https://pve.proxmox.com/pve-docs/api-viewer/).

## Scope

PBS-only objects such as remotes, sync jobs, prune jobs, verification jobs and S3 endpoints are
intentionally absent, because PVE does not expose equivalent configuration objects; the sibling
module `datajt-proxmox_backup_server` covers them. PVE's scheduled vzdump jobs are managed with
`pve_backup_job`.

## Immutable types

The `type` attribute of a storage, realm or notification target cannot be changed after creation.
The module rejects such changes before calling PVE; set `ensure => absent` and re-create the
resource with the new type.

## Storage and backup jobs

```puppet
pve_storage { 'backup-nfs':
  ensure     => present,
  type       => 'nfs',
  server     => 'nfs.example.com',
  nfs_export => '/srv/pve-backups',
  content    => 'backup',
}

pve_backup_job { 'nightly':
  ensure        => present,
  enabled       => true,
  job_schedule  => 'daily',
  storage       => 'backup-nfs',
  mode          => 'snapshot',
  all           => true,
  prune_backups => 'keep-daily=7,keep-weekly=4',
}
```

Backup job `vmid` and `exclude` values accept either PVE's comma-separated property-string format
or arrays of guest IDs. Arrays are converted before being sent to PVE, and declaration order does
not affect comparison.

## Users, groups, roles and ACLs

```puppet
pve_user { 'automation@pve':
  ensure => present,
  enable => true,
}

pve_acl { '/|automation@pve|PVEAuditor':
  ensure    => present,
  propagate => true,
}
```

- `pve_acl` is titled `path|ugid|role`. Group ACLs use a leading `@` in the `ugid` segment
  (`/|@admins|PVEAdmin`), matching PVE's own `user.cfg` syntax; token ACLs use the full token ID.
- `pve_role` manages custom access roles only. PVE's built-in (`special`) roles such as `PVEAdmin`
  or `PVEAuditor` are read-only and excluded from `get`.
- `pve_group` manages group existence and `comment`. Group membership is reported read-only via
  `members`; set it through `pve_user`'s `groups` attribute, or leave it to realm sync (OpenID
  `groups-claim` / `groups-autocreate`). Declaring synced groups in Puppet is harmless, but
  managing their membership here would fight the sync.
- `pve_user.password` is set with `pveum passwd` on the node; see
  [Secret drift detection](secret-drift.md#password-changes-use-pveum).

## Notification targets

Webhook bodies and header/secret values are declared as plain text. The provider handles PVE's
required base64 and property-string encoding:

```puppet
pve_notification_target { 'webhook-alerts':
  type        => 'webhook',
  url         => 'https://hooks.example.com/notify',
  http_method => 'post',
  body        => '{"message":"{{ message }}"}',
  header      => [{ 'name' => 'Content-Type', 'value' => 'application/json' }],
}

pve_notification_matcher { 'errors-to-webhook':
  target         => ['webhook-alerts'],
  match_severity => ['error', 'warning'],
}
```

`smtp_password`, `token` and `secret` are drift-checked against `/etc/pve/priv/notifications.cfg`;
see [Secret drift detection](secret-drift.md).

## Singletons: node and datacenter configuration

`pve_node_config` discovers every node returned by `/nodes`; use the actual PVE node name, not
`localhost`. Node configurations cannot be deleted, so `ensure => absent` fails explicitly.

`pve_datacenter_config` manages the cluster-wide `datacenter.cfg` exposed at `/cluster/options`.
PVE has exactly one such configuration; declare it with the title `datacenter`. Like
`pve_node_config`, it cannot be deleted and rejects `ensure => absent`.

```puppet
pve_datacenter_config { 'datacenter':
  email_from => 'pve@example.com',
  keyboard   => 'en-us',
}
```

## Resources class ordering

`proxmox_virtual_environment::resources` infers dependencies between related entries declared in
its Hiera hashes: realms and groups before users; users, groups, roles and tokens before ACLs;
users before API tokens; storage and pools before backup jobs; notification targets before
matchers. References to resources not declared through this class are left unconstrained.
