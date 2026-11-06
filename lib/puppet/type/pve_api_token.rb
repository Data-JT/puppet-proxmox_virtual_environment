# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'pve_api_token',
  docs:  <<~DOC,
    @summary Manages a Proxmox Virtual Environment API token.

    PVE returns a generated token secret only during creation. Set `secret_file` to
    retain it on the Puppet agent without exposing it in reports or logs.

    @example Create a token and retain its generated secret
      pve_api_token { 'automation@pve!ci':
        ensure      => present,
        privsep     => true,
        comment     => 'CI automation',
        secret_file => '/etc/puppetlabs/puppet/pve-ci-token.secret',
      }
  DOC
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this API token should exist.',
      default: 'present',
    },
    tokenid: {
      type:      'String',
      desc:      'Full token ID in user@realm!tokenname format.',
      behaviour: :namevar,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    privsep: {
      type: 'Optional[Boolean]',
      desc: 'Restrict the token to a subset of its owning user permissions.',
    },
    expire: {
      type: 'Optional[Integer]',
      desc: 'Expiry as a Unix timestamp. 0 or unset means no expiry.',
    },
    secret_file: {
      type: 'Optional[String]',
      behaviour: :parameter,
      desc: 'Agent-local file receiving the one-time token secret on creation, written with mode 0600.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_api_token)
Puppet::Type::PveSensitiveParameters.register(:pve_api_token)
