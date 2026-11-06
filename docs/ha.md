# High availability

What `pve_ha_resource` manages. All attributes are documented in
[REFERENCE.md](../REFERENCE.md#pve_ha_resource).

```puppet
pve_ha_resource { 'vm:114':
  ensure      => present,
  state       => 'started',
  max_restart => 2,
  comment     => 'Managed by Puppet',
}
```

```yaml
proxmox_virtual_environment::resources::ha_resources:
  'vm:114':
    state: started
    max_restart: 2
    comment: Managed by Puppet
```

`pve_ha_resource` is keyed by the HA service ID including the guest-type prefix (`vm:` for QEMU
guests, `ct:` for containers). The guest type comes from that prefix, so there is no separate
`type` attribute.

The resource manages HA membership, not the guest's live power state. `state => 'stopped'` tells
the HA manager to keep the guest down; it does not create or destroy the guest, and
`ensure => absent` leaves the guest running exactly as it is, merely unprotected. HA groups are
referenced by name through `group`; the module does not manage the groups themselves.
