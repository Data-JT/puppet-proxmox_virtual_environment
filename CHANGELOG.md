# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The Quality workflow also runs the unit tests on OpenVox 9.
- Data JT banner and an About section in the README; `metadata.json` names Data JT as the
  author.

## [0.1.0] - 2026-11-06

Initial release.

### Added

- Supports Puppet 8 and 9 (tested on 8) on Debian 12 (PVE 8.x) and Debian 13 (PVE 9.x). The
  module has no Forge dependencies; the Resource API it builds on ships with Puppet.
- `proxmox_virtual_environment` class that writes the API transport credentials to a
  `root:root` mode `0600` file, with the parameters `token_id`, `token_secret`,
  `cluster_manager`, `host`, `port`, `ssl_verify`, `ssl_ca_file` and `config_file`. TLS
  certificates are verified by default against the cluster CA. When `config_file` points
  elsewhere, a symlink is created at the provider discovery path.
- The transport file and its provider discovery path follow the agent's own Puppet
  confdir (fact `proxmox_virtual_environment_confdir`), not the compiling server's, so an
  OpenVox/AIO server can compile for a Debian-packaged agent.
- API requests time out after 10 seconds connecting and 60 seconds reading.
- `proxmox_virtual_environment::resources` class that declares resources from Hiera hashes
  and orders related entries declared through it.
- Resource types: `pve_acl`, `pve_api_token`, `pve_backup_job`, `pve_datacenter_config`,
  `pve_group`, `pve_ha_resource`, `pve_node_config`, `pve_notification_matcher`,
  `pve_notification_target`, `pve_pool`, `pve_realm`, `pve_role`, `pve_storage` and
  `pve_user`.
- Software Defined Networking types: `pve_sdn_zone`, `pve_sdn_vnet`, `pve_sdn_subnet`,
  `pve_sdn_controller`, `pve_sdn_ipam` and `pve_sdn_dns`, ordered automatically. The
  configuration types write pending state only and report it in a read-only
  `pending_state` property. Applying is opt-in through `pve_sdn_apply`, which is out of
  sync while pending changes exist, lists them in `pending_objects`, and with
  `noop => true` reports them without touching the network. The apply waits for the PVE
  worker task, up to 300 seconds by default (its `timeout` attribute), and fails
  unless it exits OK.
- `pve_ha_resource` manages HA membership, keyed by service ID such as `vm:114`. It never
  creates, destroys or power-cycles a guest.
- Provider writes are restricted to the node named in `cluster_manager`; every other node
  can discover state but fails closed on create, update and delete.
- Drift detection and enforcement for every managed secret: changing a secret in Hiera
  rotates it on the next run. Secrets PVE keeps under `/etc/pve/priv` are compared against
  those copies, which requires the agent to run on the PVE node as root; a declared secret
  whose store cannot be read fails the run. `pve_storage` `encryption_key`, `pve_realm`
  `client_key`, `pve_sdn_ipam` `token` and `pve_sdn_dns` `key` are compared over the API.
- `pve_user` password changes are applied with `pveum passwd` on the node, because PVE
  refuses API-token authentication on `PUT /access/password`.
- Secret attributes are redacted from change notices, report events, PuppetDB and
  `last_run_report.yaml`.
- `delete_properties` clears optional properties on `pve_api_token`, `pve_backup_job`,
  `pve_datacenter_config`, `pve_ha_resource`, `pve_node_config`,
  `pve_notification_matcher`, `pve_notification_target`, `pve_realm`,
  `pve_sdn_controller`, `pve_sdn_dns`, `pve_sdn_ipam`, `pve_sdn_subnet`, `pve_sdn_vnet`,
  `pve_sdn_zone` and `pve_storage`.
- Optional `secret_file` on `pve_api_token` retains the one-time token secret on the agent
  with mode `0600`.
- Property-string attributes are compared parsed, so PVE's key ordering does not cause
  drift.
- `pve_api_request` task for ad-hoc API calls, and `sdn_apply` task for a one-off SDN apply
  with a `dry_run` preview.
- `tools/pve_hiera_import.rb`, a checkout-only tool that generates Hiera data from an
  existing PVE cluster. It is not part of the Forge package.
- Least-privilege token setup guidance in the README.

[Unreleased]: https://github.com/Data-JT/puppet-proxmox_virtual_environment/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Data-JT/puppet-proxmox_virtual_environment/releases/tag/v0.1.0
