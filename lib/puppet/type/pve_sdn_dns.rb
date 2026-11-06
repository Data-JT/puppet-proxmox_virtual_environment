# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'
require_relative 'pve_sdn_apply_autobefore'

Puppet::ResourceApi.register_type(
  name:     'pve_sdn_dns',
  docs:     <<~DOCS,
    Manages a Proxmox Virtual Environment SDN DNS backend.

    **Unlike the other SDN types, this one needs no apply.** DNS backends are
    not part of the pending/running split: `/cluster/sdn/dns` accepts neither
    `pending` nor `running`, there is no dns section in
    /etc/pve/sdn/.running-config, and PVE calls the backend live when it
    registers a record. A change here takes effect immediately, so this type has
    no `pending_state` property and `pve_sdn_apply` ignores it.
  DOCS
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this DNS backend should exist.',
      default: 'present',
    },
    dns: {
      type:      'String',
      desc:      'The SDN DNS identifier.',
      behaviour: :namevar,
    },
    type: {
      type:      "Enum['powerdns']",
      desc:      'DNS plugin type. Cannot be changed after creation. PowerDNS is the only backend PVE implements.',
      behaviour: :init_only,
    },
    url: {
      type: 'Optional[String]',
      desc: 'PowerDNS API URL, e.g. http://powerdns.example.com:8081/api/v1/servers/localhost. Required by PVE when creating the backend.',
    },
    key: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'PowerDNS API key. PVE stores it in cleartext in /etc/pve/sdn/dns.cfg and returns it, so it is compared directly and drift is detected. Redacted from Puppet reports.',
      sensitive: true,
    },
    ttl: {
      type: 'Optional[Integer]',
      desc: 'TTL applied to records this backend creates.',
    },
    reversemaskv6: {
      type: 'Optional[Integer]',
      desc: 'Prefix length used when generating IPv6 reverse zones.',
    },
    fingerprint: {
      type: 'Optional[String]',
      desc: 'SHA-256 fingerprint of the PowerDNS TLS certificate, for a private CA.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_sdn_dns)
Puppet::Type::PveSensitiveParameters.register(:pve_sdn_dns)
Puppet::Type::PveSdnApplyAutobefore.register(:pve_sdn_dns)
