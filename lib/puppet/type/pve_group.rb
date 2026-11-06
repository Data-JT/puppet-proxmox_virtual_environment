# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'pve_group',
  docs:  'Manages a Proxmox Virtual Environment user group.',

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this group should exist.',
      default: 'present',
    },
    groupid: {
      type:      'String',
      desc:      'The group ID.',
      behaviour: :namevar,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    members: {
      type:      'Optional[Array[String]]',
      desc:      'Read-only. User IDs that are members of this group, as reported by PVE. Membership is set on the pve_user resource (groups attribute) or by realm sync, not here.',
      behaviour: :read_only,
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_group)
Puppet::Type::PveSensitiveParameters.register(:pve_group)
