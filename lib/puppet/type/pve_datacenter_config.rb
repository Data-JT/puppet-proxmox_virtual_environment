# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'pve_datacenter_config',
  docs:  <<-DOC,
    Manages the cluster-wide PVE datacenter configuration (datacenter.cfg),
    exposed at GET/PUT /cluster/options. This is a singleton resource; declare
    it with the title 'datacenter'.
  DOC
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Keeps the datacenter configuration in sync. PVE rejects absent because it cannot be deleted.',
      default: 'present',
    },
    name: {
      type:      "Enum['datacenter']",
      desc:      "Must be 'datacenter'; PVE has exactly one cluster-wide configuration.",
      behaviour: :namevar,
    },
    description: {
      type: 'Optional[String]',
      desc: 'Datacenter description shown in the web UI notes panel.',
    },
    keyboard: {
      type: "Optional[Enum['de', 'de-ch', 'da', 'en-gb', 'en-us', 'es', 'fi', 'fr', 'fr-be', 'fr-ca', 'fr-ch', 'hu', 'is', 'it', 'ja', 'lt', 'mk', 'nl', 'no', 'pl', 'pt', 'pt-br', 'sv', 'sl', 'tr']]",
      desc: 'Default keyboard layout for the VNC console.',
    },
    language: {
      type: 'Optional[String]',
      desc: 'Default GUI language.',
    },
    console: {
      type: "Optional[Enum['applet', 'vv', 'html5', 'xtermjs']]",
      desc: 'Default console viewer.',
    },
    mac_prefix: {
      type: 'Optional[String]',
      desc: "Prefix for auto-generated guest MAC addresses (e.g. 'BC:24:11').",
    },
    email_from: {
      type: 'Optional[String]',
      desc: 'Email address used as the sender for notifications (defaults to root@$hostname).',
    },
    http_proxy: {
      type: 'Optional[String]',
      desc: 'HTTP proxy used by PVE for outgoing connections (e.g. http://proxy:8080).',
    },
    max_workers: {
      type: 'Optional[Integer]',
      desc: 'Maximum number of workers per node for actions such as "stop all VMs".',
    },
    bwlimit: {
      type: 'Optional[String]',
      desc: 'I/O bandwidth limits in PVE property-string format (e.g. "default=10240,migration=5120").',
    },
    migration: {
      type: 'Optional[String]',
      desc: 'Cluster-wide migration settings in PVE property-string format (e.g. "type=secure,network=10.0.0.0/24").',
    },
    next_id: {
      type: 'Optional[String]',
      desc: 'Range for free VMID auto-selection in PVE property-string format (e.g. "lower=100,upper=1000000").',
    },
    crs: {
      type: 'Optional[String]',
      desc: 'Cluster resource scheduler settings in PVE property-string format.',
    },
    ha: {
      type: 'Optional[String]',
      desc: 'Cluster-wide HA settings in PVE property-string format (e.g. "shutdown_policy=migrate").',
    },
    fencing: {
      type: "Optional[Enum['watchdog', 'hardware', 'both']]",
      desc: 'Fencing mode of the HA cluster.',
    },
    tag_style: {
      type: 'Optional[String]',
      desc: 'Tag display/sorting options in PVE property-string format (e.g. "shape=full,ordering=alphabetical").',
    },
    registered_tags: {
      type: 'Optional[Array[String]]',
      desc: 'Tags that may only be set/removed by users with Sys.Modify on /.',
    },
    user_tag_access: {
      type: 'Optional[String]',
      desc: 'Privilege options for user-settable tags in PVE property-string format (e.g. "user-allow=existing").',
    },
    u2f: {
      type: 'Optional[String]',
      desc: 'U2F configuration in PVE property-string format.',
    },
    webauthn: {
      type: 'Optional[String]',
      desc: 'WebAuthn configuration in PVE property-string format (e.g. "rp=Example,origin=https://...,id=...").',
    },
    notify_settings: {
      type: 'Optional[String]',
      desc: 'Cluster-wide notification settings in PVE property-string format.',
    },
    consent_text: {
      type: 'Optional[String]',
      desc: 'Consent text displayed before login.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_datacenter_config)
Puppet::Type::PveSensitiveParameters.register(:pve_datacenter_config)
