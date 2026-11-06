# Clearing optional properties

How to remove a value on the PVE side, since removing an attribute from a manifest does not.

Removing an attribute from a manifest only stops Puppet managing it; the value stays set on the
PVE side. To clear an optional property, list its PVE API name (the hyphenated name the API uses,
such as `mailnotification`, not the Puppet attribute name) in `delete_properties`:

```puppet
pve_backup_job { 'nightly':
  delete_properties => ['mailto', 'mailnotification'],
}
```

The provider passes the list to the endpoint's `delete` parameter on update, and only while one of
the named properties is still set, so the resource converges instead of re-sending the deletion on
every run. A name the provider does not map is rejected, because its removal could never be
observed. Create requests never carry the parameter.

The following types support `delete_properties`: `pve_api_token`, `pve_backup_job`,
`pve_datacenter_config`, `pve_ha_resource`, `pve_node_config`, `pve_notification_matcher`,
`pve_notification_target`, `pve_realm`, `pve_sdn_controller`, `pve_sdn_dns`, `pve_sdn_ipam`,
`pve_sdn_subnet`, `pve_sdn_vnet`, `pve_sdn_zone` and `pve_storage`.
