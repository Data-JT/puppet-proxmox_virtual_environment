# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'
require_relative 'pve_sdn_apply_autobefore'

Puppet::ResourceApi.register_type(
  name:     'pve_sdn_controller',
  docs:     <<~DOCS,
    Manages a Proxmox Virtual Environment SDN controller.

    Controllers drive the routing daemon (FRR) for EVPN, BGP and IS-IS zones.
    An evpn zone requires one.

    **This resource writes pending configuration only.** A change here lands in
    /etc/pve/sdn/controllers.cfg and alters nothing on the wire until the
    separate `PUT /cluster/sdn` apply runs. This type never performs that apply;
    declare `pve_sdn_apply` to opt in, or `pve_sdn_apply { 'sdn': noop => true }`
    to have every run report unapplied changes without touching the network.

    Attributes are grouped by the plugin type that accepts them.
  DOCS
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this SDN controller should exist.',
      default: 'present',
    },
    controller: {
      type:      'String[1,64]',
      desc:      'The SDN controller identifier.',
      behaviour: :namevar,
    },
    type: {
      type:      "Enum['evpn', 'bgp', 'isis', 'faucet']",
      desc:      'Controller plugin type. Cannot be changed after creation. The faucet plugin is experimental and unmaintained upstream.',
      behaviour: :init_only,
    },
    pending_state: {
      type:      "Optional[Enum['new', 'changed', 'deleted']]",
      desc:      'Read-only. Whether this controller differs from the applied running configuration. Absent means the controller is applied.',
      behaviour: :read_only,
    },

    # ── evpn and bgp ─────────────────────────────────────────────────────────
    asn: {
      type: 'Optional[Integer]',
      desc: 'Autonomous system number.',
    },
    peers: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of BGP peer addresses. Compared as an unordered set.',
    },
    fabric: {
      type: 'Optional[String]',
      desc: 'SDN fabric used as the underlay for this EVPN controller. Fabrics themselves are not managed by this module; the name is passed through to PVE.',
    },

    # ── evpn ─────────────────────────────────────────────────────────────────
    peer_group_name: {
      type: 'Optional[String]',
      desc: 'Name of the BGP peer group for this EVPN controller. Defaults to VTEP.',
    },

    # ── bgp ──────────────────────────────────────────────────────────────────
    node: {
      type: 'Optional[String]',
      desc: 'Cluster node this BGP controller configures. A bgp controller is per-node.',
    },
    ebgp: {
      type: 'Optional[Boolean]',
      desc: 'Use eBGP (remote-as external) rather than iBGP.',
    },
    ebgp_multihop: {
      type: 'Optional[Integer]',
      desc: 'Maximum hop count for eBGP peers.',
    },
    bgp_mode: {
      type: "Optional[Enum['auto', 'external', 'internal']]",
      desc: 'Whether to use eBGP or iBGP. Auto decides from the BGP controller and falls back to iBGP.',
    },
    bgp_multipath_as_path_relax: {
      type: 'Optional[Boolean]',
      desc: 'Consider AS paths of equal length but differing content for multipath.',
    },
    loopback: {
      type: 'Optional[String]',
      desc: 'Loopback or dummy interface providing the router IP.',
    },
    route_map_in: {
      type: 'Optional[String]',
      desc: 'Route map applied to incoming routes. Route maps themselves are not managed by this module.',
    },
    route_map_out: {
      type: 'Optional[String]',
      desc: 'Route map applied to outgoing routes. Route maps themselves are not managed by this module.',
    },

    # ── isis ─────────────────────────────────────────────────────────────────
    isis_domain: {
      type: 'Optional[String]',
      desc: 'Name of the IS-IS domain.',
    },
    isis_ifaces: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of interfaces on which IS-IS is active. Compared as an unordered set.',
    },
    isis_net: {
      type: 'Optional[String]',
      desc: 'Network entity title for this node in the IS-IS network.',
    },
    nodes: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of cluster nodes this controller applies to. Compared as an unordered set.',
    },

    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_sdn_controller)
Puppet::Type::PveSensitiveParameters.register(:pve_sdn_controller)
Puppet::Type::PveSdnApplyAutobefore.register(:pve_sdn_controller)
