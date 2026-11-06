# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:     'pve_acl',
  docs:     'Manages a Proxmox Virtual Environment ACL entry.',

  title_patterns: [
    {
      pattern: %r{^(?<acl_path>[^|]+)\|(?<ugid>[^|]+)\|(?<role>[^|]+)$},
      desc:    'Where acl_path, ugid and role are provided with pipe separators',
    },
    {
      pattern: %r{^(?<acl_path>.+)$},
      desc:    'Where only the acl_path is provided (requires ugid and role params)',
    },
  ],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this ACL entry should exist.',
      default: 'present',
    },
    acl_path: {
      type:      'String',
      desc:      'The ACL path (e.g. /, /storage/local).',
      behaviour: :namevar,
    },
    ugid: {
      type:      'String',
      desc:      'The user, group, or token ID this ACL applies to. Group principals are written with a leading @ (e.g. @admins), matching PVE user.cfg syntax.',
      behaviour: :namevar,
    },
    role: {
      type:      'String',
      desc:      'The role to assign.',
      behaviour: :namevar,
    },
    propagate: {
      type:    'Boolean',
      desc:    'Whether the ACL entry propagates to sub-paths.',
      default: true,
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_acl)
Puppet::Type::PveSensitiveParameters.register(:pve_acl)
