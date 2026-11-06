# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'pve_pool',
  docs:  'Manages a Proxmox Virtual Environment resource pool.',

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this pool should exist. PVE only allows deleting empty pools.',
      default: 'present',
    },
    poolid: {
      type:      'String',
      desc:      'The pool ID.',
      behaviour: :namevar,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_pool)
Puppet::Type::PveSensitiveParameters.register(:pve_pool)
