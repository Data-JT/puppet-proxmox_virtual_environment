# Software-defined networking

Read this before managing SDN. PVE splits SDN into two phases, and getting the split wrong is the
difference between a quiet Puppet run and every overlay guest in the cluster losing its network.
The attributes of the `pve_sdn_*` types are documented in [REFERENCE.md](../REFERENCE.md#pve_sdn_zone).

## Pending and applied state

1. Writing a zone, VNet, subnet or controller lands in `/etc/pve/sdn/*.cfg` and changes nothing
   on the wire. That is a *pending* change.
2. `PUT /cluster/sdn` regenerates `/etc/network/interfaces.d/sdn` on every node and reloads
   networking there. That is the *apply*.

The `pve_sdn_*` types in this module only ever do step 1. Nothing in an ordinary agent run
performs step 2: an implicit apply on a 30-minute cycle would blip every guest on the overlay as a
side effect of an unrelated property change.

The obvious consequence is a trap: rewrite a VXLAN zone's `peers` in Hiera and Puppet reports
`Updated zone 'zone1'` and goes green, while the nodes keep forwarding on the old underlay
indefinitely. Two things make that visible.

**Per object.** Zones, VNets, subnets and controllers carry a read-only `pending_state` property
(`new`, `changed` or `deleted`; absent once applied):

```console
$ puppet resource pve_sdn_zone zone1
pve_sdn_zone { 'zone1':
  ensure        => 'present',
  type          => 'vxlan',
  peers         => '192.0.2.11,192.0.2.12',
  pending_state => 'changed',
}
```

**Cluster-wide.** `pve_sdn_apply` is out of sync whenever any SDN object differs from the running
configuration, and names the offenders in `pending_objects`. Declaring it is how you opt in to
applying:

```puppet
# Apply pending SDN changes during the agent run. Reloads networking on every
# cluster node; only declare this where that is acceptable.
pve_sdn_apply { 'sdn': }
```

```puppet
# Report unapplied SDN changes on every run, and never touch the network.
pve_sdn_apply { 'sdn':
  noop => true,
}
```

Not declaring `pve_sdn_apply` at all leaves the module unable to apply anything. That is the
default and the recommended starting point.

The apply waits for the PVE worker task and fails the resource unless it exits `OK`, so a
half-finished apply is not reported as a successful change. It waits up to 300 seconds by
default; set `timeout` to change that, or `wait => false` to fire and forget.

## A zone, VNet and subnet

```puppet
pve_sdn_zone { 'zone1':
  ensure => present,
  type   => 'vxlan',
  peers  => '192.0.2.11,192.0.2.12',
}

pve_sdn_vnet { 'vnet1':
  ensure => present,
  zone   => 'zone1',
}

pve_sdn_subnet { 'vnet1|198.51.100.0/24':
  ensure  => present,
  gateway => '198.51.100.1',
  snat    => true,
}
```

The same objects in Hiera, through `proxmox_virtual_environment::resources`:

```yaml
proxmox_virtual_environment::resources::sdn_zones:
  zone1:
    type: vxlan
    peers: '192.0.2.11,192.0.2.12'

proxmox_virtual_environment::resources::sdn_vnets:
  vnet1:
    zone: zone1

proxmox_virtual_environment::resources::sdn_subnets:
  'vnet1|198.51.100.0/24':
    gateway: 198.51.100.1
    snat: true

proxmox_virtual_environment::resources::sdn_apply:
  sdn:
    noop: true
```

## Applying by hand

For a maintenance window, the `sdn_apply` task does the same thing without a catalog, and can
preview the change first:

```sh
# Show what would change on one node, without touching anything
bolt task run proxmox_virtual_environment::sdn_apply --targets pve01.example.com \
  host=localhost token_id=... token_secret=... dry_run=true node=pve01

# Apply, waiting for the worker task
bolt task run proxmox_virtual_environment::sdn_apply --targets pve01.example.com \
  host=localhost token_id=... token_secret=...
```

Pass the token secret through a parameters file or an inventory secret backend rather than on the
command line; see [Ad-hoc API access](api-access.md) for the pattern.

## IPAM and DNS are different

`pve_sdn_ipam` and `pve_sdn_dns` are not part of the pending/running split. Their endpoints
accept neither `pending` nor `running`, they have no section in `/etc/pve/sdn/.running-config`,
and PVE consults them live. A change to either takes effect immediately, needs no apply, and is
ignored by `pve_sdn_apply`.

Their secrets (`token` and `key`) round-trip through the API in cleartext: `/etc/pve/sdn/ipams.cfg`
and `dns.cfg` are handed back unfiltered. Both are therefore ordinary properties with real drift
detection, redacted from Puppet reports. See [Secret drift detection](secret-drift.md).

## Subnet identity

PVE does not key subnets by their CIDR. It derives an identifier by prefixing the VNet's zone and
replacing the slash with a dash, so `198.51.100.0/24` in a VNet belonging to zone `zone1` becomes
`zone1-198.51.100.0-24`, and only the create endpoint accepts a bare CIDR. `pve_sdn_subnet` is
therefore keyed by VNet and CIDR with a pipe-separated title, in the same style as `pve_acl`; the
provider derives PVE's identifier itself and reports it as `subnet_id`.

## The global SDN lock

PVE 9 guards SDN mutations with `/etc/pve/sdn/.lock-token`. This module never acquires that lock:
a cluster-wide lock left behind by a crashed agent would block the web UI indefinitely. If another
client holds it, writes fail with an actionable error naming `pvesh delete /cluster/sdn/lock --force`.

`digest` optimistic concurrency is deliberately unused. The digest covers a whole section config
file, and each resource reads its state at its own position in the catalog, so writing one zone
would invalidate the digest already read for the next one and every subsequent SDN write in the
run would fail.

## Not managed

Fabrics, prefix lists and route maps are not modelled. Fabrics are a two-level model whose
attributes are JSON arrays of property strings with an array-valued `delete`, and prefix lists and
route maps are ordered-entry sub-collections; neither shape has a precedent in this module.
`POST /cluster/sdn/rollback` (discard pending changes) is not modelled either, because a resource
doing that would fight the config types on every run; use `pvesh` for it.
