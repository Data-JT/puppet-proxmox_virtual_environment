# Token permissions

How to create the PVE user and API token the module authenticates with, and which privileges
each resource type needs.

## User and token

```sh
pveum user add puppet@pve
pveum user token add puppet@pve puppet --privsep 1      # prints the secret once
```

With token privilege separation (`--privsep 1`), the token's effective permissions are the
intersection of the user's and the token's own ACLs, so grant the required role to both
`puppet@pve` and `puppet@pve!puppet`.

Do not grant the token blanket `Administrator` access at `/`. Grant only the roles and ACL paths
needed for the resource types in the node's catalog. For example, a token that only manages
storage definitions can use a custom role scoped to `/storage`:

```sh
pveum role add PuppetStorage --privs 'Datastore.Audit Datastore.Allocate'
pveum acl modify /storage --users puppet@pve --roles PuppetStorage
pveum acl modify /storage --tokens 'puppet@pve!puppet' --roles PuppetStorage
```

## Privileges per resource type

Use this matrix as a least-privilege starting point. PVE checks permissions per API method, and
checks can change between PVE releases, so confirm every method used by the declared resources in
the [PVE API viewer](https://pve.proxmox.com/pve-docs/api-viewer/) for the deployed PVE version.

| Resource type | Typical ACL path | Required privilege categories |
|---|---|---|
| `pve_storage` | `/storage` | `Datastore.Audit`, `Datastore.Allocate` |
| `pve_backup_job` | `/` | `Sys.Audit`, `Sys.Modify`, plus access to referenced guests and storage |
| `pve_user`, `pve_api_token` | `/access` | `User.Modify` |
| `pve_group` | `/access/groups` | `Group.Allocate` |
| `pve_acl`, `pve_role` | `/access` and delegated target paths | `Permissions.Modify` |
| `pve_realm` | `/access/realm` | `Realm.Allocate` |
| `pve_node_config` | `/nodes/{node}` | `Sys.Audit`, `Sys.Modify` |
| `pve_notification_target`, `pve_notification_matcher` | `/mapping/notifications` | `Mapping.Audit`, `Mapping.Modify` |
| `pve_pool` | `/pool` | `Pool.Audit`, `Pool.Allocate` |
| `pve_datacenter_config` | `/` | `Sys.Audit`, `Sys.Modify` |
| `pve_ha_resource` | `/` | `Sys.Audit`, `Sys.Console` |
| `pve_sdn_*` | `/sdn` | `SDN.Audit`, `SDN.Allocate` |

`pve_user` password changes do not use the token: they run `pveum passwd` as root on the node, so
the token needs no privilege for them. See [Secret drift detection](secret-drift.md#password-changes-use-pveum).

The providers discover existing resources before applying changes, so the token also needs the
`*.Audit` privilege of every type it manages. Incomplete visibility can make an existing object
appear absent and cause a failed creation attempt.
