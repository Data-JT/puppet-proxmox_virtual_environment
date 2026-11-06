# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'pve_role',
  docs:  'Manages a custom Proxmox Virtual Environment access role.',
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this role should exist. Built-in (special) PVE roles cannot be managed.',
      default: 'present',
    },
    roleid: {
      type:      'String',
      desc:      'The role ID.',
      behaviour: :namevar,
    },
    privs: {
      type:    'Optional[Array[String]]',
      desc:    'Privileges granted by this role (e.g. VM.Audit, Datastore.AllocateSpace).',
      default: [],
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_role)
Puppet::Type::PveSensitiveParameters.register(:pve_role)
