# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:     'pve_user',
  docs:     'Manages a Proxmox Virtual Environment user.',
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this user should exist.',
      default: 'present',
    },
    userid: {
      type:      'String',
      desc:      'The user ID in user@realm format.',
      behaviour: :namevar,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    email: {
      type: 'Optional[String]',
      desc: 'Email address of the user.',
    },
    enable: {
      type:    'Boolean',
      desc:    'Whether the user account is enabled.',
      default: true,
    },
    expire: {
      type: 'Optional[Integer]',
      desc: 'Account expiry time as a Unix timestamp (0 means no expiry).',
    },
    firstname: {
      type: 'Optional[String]',
      desc: 'First name of the user.',
    },
    lastname: {
      type: 'Optional[String]',
      desc: 'Last name of the user.',
    },
    groups: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of PVE groups.',
    },
    keys: {
      type: 'Optional[String]',
      desc: 'User public keys.',
    },
    password: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'User password. Sent on creation; changes are applied with "pveum passwd" because PVE refuses API-token auth on PUT /access/password. Compared against /etc/pve/priv/shadow.cfg.',
      sensitive: true,
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_user)
Puppet::Type::PveSensitiveParameters.register(:pve_user)
