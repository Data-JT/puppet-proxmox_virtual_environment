# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'pve_notification_matcher',
  docs:  'Manages a Proxmox Virtual Environment notification matcher (routing rule).',
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this notification matcher should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'The matcher name.',
      behaviour: :namevar,
    },
    target: {
      type: 'Optional[Array[String]]',
      desc: 'Notification target names this matcher routes matched notifications to.',
    },
    match_severity: {
      type: 'Optional[Array[String]]',
      desc: 'Severity levels to match. Valid values: info, notice, warning, error, unknown.',
    },
    match_calendar: {
      type: 'Optional[Array[String]]',
      desc: 'Calendar schedule expressions to match (e.g. "mon-fri 09:00-17:00").',
    },
    match_field: {
      type: 'Optional[Array[String]]',
      desc: 'Metadata field matchers (e.g. "exact:type=gc", "regex:storage=^backup-.*$").',
    },
    mode: {
      type:    'Optional[Enum[all, any]]',
      desc:    'Whether all (AND) or any (OR) match rules must be satisfied. Defaults to all.',
    },
    invert_match: {
      type: 'Optional[Boolean]',
      desc: 'Invert the overall match result.',
    },
    disable: {
      type: 'Optional[Boolean]',
      desc: 'Disable this matcher.',
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_notification_matcher)
Puppet::Type::PveSensitiveParameters.register(:pve_notification_matcher)
