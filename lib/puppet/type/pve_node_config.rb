# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'pve_node_config',
  docs:  'Manages PVE node-level configuration, including the Notes section visible in the web UI.',
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Keeps the node configuration in sync. PVE rejects absent because node configuration cannot be deleted.',
      default: 'present',
    },
    node: {
      type:      'String',
      desc:      'PVE node name as returned by GET /nodes (the short hostname, e.g. "pve01").',
      behaviour: :namevar,
    },
    description: {
      type: 'Optional[String]',
      desc: 'Free-form text shown in the Notes panel of the PVE web UI (supports Markdown).',
    },
    location: {
      type: 'Optional[String]',
      desc: 'Node location in PVE property-string format.',
    },
    wakeonlan: {
      type: 'Optional[String]',
      desc: 'Wake-on-LAN settings in PVE property-string format.',
    },
    startall_onboot_delay: {
      type: 'Optional[Integer]',
      desc: 'Delay before starting all on-boot guests.',
    },
    ballooning_target: {
      type: 'Optional[Integer[0, 100]]',
      desc: 'RAM usage target for ballooning, as a percentage.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_node_config)
Puppet::Type::PveSensitiveParameters.register(:pve_node_config)
