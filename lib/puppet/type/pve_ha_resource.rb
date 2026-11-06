# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name: 'pve_ha_resource',
  docs: <<~DOCS,
    Manages Proxmox Virtual Environment HA resource membership — which guests the
    HA manager keeps running, and how hard it tries.

    Note this manages HA *membership*, not the guest's live power state. Setting
    state to 'stopped' tells the HA manager to keep the guest stopped (and not
    restart it after a node failure); it does not create or destroy the guest.
    Removing the resource (ensure => absent) leaves the guest running exactly as
    it is, merely unprotected.
  DOCS
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type: 'Enum[present, absent]',
      desc: 'Whether this guest should be under HA management.',
      default: 'present',
    },
    sid: {
      # The prefix is what tells PVE the resource type, so it is required here
      # rather than exposing a separate 'type' attribute: PVE derives type from
      # the sid on create, and rejects 'type' as a parameter on update.
      type: 'Pattern[/\A(vm|ct):[0-9]+\z/]',
      desc: "HA service ID, including the guest-type prefix — e.g. 'vm:114' for a QEMU guest or 'ct:105' for a container.",
      behaviour: :namevar,
    },
    state: {
      # 'ignored' means the HA stack keeps the entry but stops acting on it at
      # all, which is different from 'disabled' (HA owns it and keeps it down).
      #
      # Keep desc a single plain string: puppet-strings' RsapiHandler cannot
      # parse a concatenated one and silently drops the WHOLE type from
      # REFERENCE.md rather than failing.
      type: "Optional[Enum['started', 'stopped', 'disabled', 'ignored']]",
      desc: 'Requested HA state: started (run it, recover after node failure), stopped (keep down, still HA-managed), disabled (keep down, never start), ignored (entry kept, HA acts on nothing).',
    },
    group: {
      type: 'Optional[String]',
      desc: 'HA group restricting which nodes may run this guest. The group must already exist.',
    },
    max_restart: {
      type: 'Optional[Integer[0]]',
      desc: 'How many times to try restarting the guest on its current node before relocating it.',
    },
    max_relocate: {
      type: 'Optional[Integer[0]]',
      desc: 'How many times to try relocating the guest to another node after restarts are exhausted.',
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

Puppet::Type::PveTransportAutorequire.register(:pve_ha_resource)
Puppet::Type::PveSensitiveParameters.register(:pve_ha_resource)
