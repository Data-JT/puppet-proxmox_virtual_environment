# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:     'pve_sdn_apply',
  docs:     <<~DOCS,
    Applies pending Proxmox Virtual Environment SDN configuration cluster-wide.

    ### Why this exists

    Every other `pve_sdn_*` type writes to /etc/pve/sdn/*.cfg and changes
    nothing on the wire. PVE only acts on those files when `PUT /cluster/sdn`
    runs, which regenerates /etc/network/interfaces.d/sdn on **every** node and
    reloads networking there. On a cluster carrying overlay guests that is a
    disruptive operation, so no other resource in this module performs it, and
    an agent run cannot trigger it as a side effect of an ordinary property
    change.

    Without this resource in the catalog, a zone whose `peers` list has been
    rewritten reports green while the nodes keep forwarding on the old underlay
    indefinitely. This resource closes that gap: it is out of sync whenever any
    zone, VNet, subnet or controller differs from the applied running
    configuration, and it names the offenders in `pending_objects`.

    ### Modes

    ```puppet
    # Apply pending SDN changes during the agent run. Reloads networking
    # cluster-wide, so only declare this where that is acceptable.
    pve_sdn_apply { 'sdn': }

    # Report unapplied SDN changes on every run and never touch the network.
    # Puppet's own noop metaparameter; the run stays corrective-free.
    pve_sdn_apply { 'sdn':
      noop => true,
    }
    ```

    Not declaring it at all leaves the module unable to apply anything, which is
    the default.

    ### Ordering

    This type automatically requires every `pve_sdn_*` resource in the catalog,
    so it observes the writes made earlier in the same run.

    ### Failure reporting

    `PUT /cluster/sdn` returns a UPID for a background worker. By default this
    resource waits for that worker and fails the resource unless it exits `OK`;
    otherwise a failed apply would be reported as a successful change. Set
    `wait => false` to fire and forget.

    ### One-off apply

    The `proxmox_virtual_environment::sdn_apply` Bolt task performs the same
    apply without a catalog, for use in a maintenance window.

    ### IPAM and DNS

    `pve_sdn_ipam` and `pve_sdn_dns` are not part of the pending/running split
    and take effect immediately, so they are deliberately not counted here.
  DOCS
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Always present. This resource represents an action on the existing SDN configuration, not an object, so absent is rejected.',
      default: 'present',
    },
    name: {
      type:      "Enum['sdn']",
      desc:      "Singleton name. PVE has exactly one SDN configuration, so the only valid title is 'sdn'.",
      behaviour: :namevar,
    },
    applied: {
      type:    'Boolean',
      desc:    'Whether the SDN running configuration matches the configured one. Only true is meaningful to declare; it is the default.',
      default: true,
    },
    pending_objects: {
      type:      'Optional[Array[String]]',
      desc:      'Read-only. SDN objects that differ from the running configuration, as "<kind>/<id>: <state>" entries, e.g. "zones/zone1: changed".',
      behaviour: :read_only,
    },
    wait: {
      type:      'Boolean',
      desc:      'Wait for the apply worker task to finish and fail the resource unless it exits OK.',
      default:   true,
      behaviour: :parameter,
    },
    timeout: {
      type:      'Integer',
      desc:      'Seconds to wait for the apply worker task before giving up.',
      default:   300,
      behaviour: :parameter,
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_sdn_apply)
Puppet::Type::PveSensitiveParameters.register(:pve_sdn_apply)

# The ordering that puts this resource after every SDN object is declared the
# other way round, as an autobefore on each object type (see
# PveSdnApplyAutobefore). Expressing it there needs no catalog scan: this type
# is a singleton whose title is always 'sdn'.
