# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'
require_relative 'pve_sdn_apply_autobefore'

Puppet::ResourceApi.register_type(
  name:     'pve_sdn_ipam',
  docs:     <<~DOCS,
    Manages a Proxmox Virtual Environment SDN IPAM backend.

    **Unlike the other SDN types, this one needs no apply.** IPAM backends are
    not part of the pending/running split: `/cluster/sdn/ipams` accepts neither
    `pending` nor `running`, there is no ipams section in
    /etc/pve/sdn/.running-config, and PVE consults the backend live when it
    allocates an address. A change here takes effect immediately, so this type
    has no `pending_state` property and `pve_sdn_apply` ignores it.

    PVE always provides a built-in `pve` IPAM. Declare this type only for an
    external NetBox or phpIPAM backend.
  DOCS
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this IPAM backend should exist.',
      default: 'present',
    },
    ipam: {
      type:      'String',
      desc:      'The SDN IPAM identifier.',
      behaviour: :namevar,
    },
    type: {
      type:      "Enum['pve', 'netbox', 'phpipam']",
      desc:      'IPAM plugin type. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    url: {
      type: 'Optional[String]',
      desc: 'API URL of the external IPAM. Required for netbox and phpipam.',
    },
    token: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'API token for the external IPAM. PVE stores it in cleartext in /etc/pve/sdn/ipams.cfg and returns it, so it is compared directly and drift is detected. Redacted from reports.',
      sensitive: true,
    },
    section: {
      type: 'Optional[Integer]',
      desc: 'phpIPAM section ID to allocate from.',
    },
    fingerprint: {
      type: 'Optional[String]',
      desc: 'SHA-256 fingerprint of the IPAM TLS certificate, for a private CA.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_sdn_ipam)
Puppet::Type::PveSensitiveParameters.register(:pve_sdn_ipam)
Puppet::Type::PveSdnApplyAutobefore.register(:pve_sdn_ipam)
