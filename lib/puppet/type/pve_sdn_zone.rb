# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'
require_relative 'pve_sdn_apply_autobefore'

Puppet::ResourceApi.register_type(
  name:     'pve_sdn_zone',
  docs:     <<~DOCS,
    Manages a Proxmox Virtual Environment SDN zone.

    **This resource writes pending configuration only.** A change here lands in
    /etc/pve/sdn/zones.cfg and alters nothing on the wire. PVE only regenerates
    /etc/network/interfaces.d/sdn and reloads networking when the separate
    `PUT /cluster/sdn` apply runs, which this type never performs -- an implicit
    apply on an ordinary agent run would blip every overlay guest in the cluster.

    Declare `pve_sdn_apply` to opt in to applying, or `pve_sdn_apply` with
    `noop => true` to have every run report unapplied changes without touching
    the network. The read-only `pending_state` property below shows the same
    thing per zone.

    Attributes are grouped by the plugin type that accepts them; PVE rejects an
    attribute that does not belong to the zone's type.
  DOCS
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this SDN zone should exist.',
      default: 'present',
    },
    zone: {
      type:      'String[1,8]',
      desc:      'The SDN zone identifier. PVE limits this to 8 characters.',
      behaviour: :namevar,
    },
    type: {
      type:      "Enum['simple', 'vlan', 'qinq', 'vxlan', 'evpn', 'faucet']",
      desc:      'Zone plugin type. Cannot be changed after creation. The faucet plugin is experimental and unmaintained upstream.',
      behaviour: :init_only,
    },
    pending_state: {
      type:      "Optional[Enum['new', 'changed', 'deleted']]",
      desc:      'Read-only. Whether this zone differs from the applied running configuration; absent means applied. Never enforced -- it makes an unapplied change visible in reports.',
      behaviour: :read_only,
    },

    # ── All zone types ───────────────────────────────────────────────────────
    nodes: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of cluster nodes this zone is deployed on. Compared as an unordered set.',
    },
    mtu: {
      type: 'Optional[Integer]',
      desc: 'MTU applied to the VNet bridges created for this zone.',
    },
    ipam: {
      type: 'Optional[String]',
      desc: 'IPAM backend used for address allocation in this zone (see pve_sdn_ipam). PVE uses the built-in "pve" IPAM when unset.',
    },
    dns: {
      type: 'Optional[String]',
      desc: 'DNS API server used to register guest records (see pve_sdn_dns).',
    },
    reversedns: {
      type: 'Optional[String]',
      desc: 'DNS API server used to register reverse records.',
    },
    dnszone: {
      type: 'Optional[String]',
      desc: 'DNS domain for registered records, e.g. example.com.',
    },
    dhcp: {
      type: "Optional[Enum['dnsmasq']]",
      desc: 'DHCP backend for this zone. Requires subnets with a dhcp_range.',
    },

    # ── vlan and qinq ────────────────────────────────────────────────────────
    bridge: {
      type: 'Optional[String]',
      desc: 'Bridge whose VLANs this zone manages. Required for vlan and qinq zones.',
    },

    # ── qinq ─────────────────────────────────────────────────────────────────
    service_vlan: {
      type: 'Optional[Integer]',
      desc: "Service-VLAN tag (the outer VLAN). Required for qinq zones. Maps to PVE's `tag`, which cannot be used as an attribute name because Puppet reserves it as a metaparameter.",
    },
    vlan_protocol: {
      type: "Optional[Enum['802.1q', '802.1ad']]",
      desc: 'Encapsulation protocol for the qinq service VLAN. Defaults to 802.1q.',
    },

    # ── vxlan and evpn ───────────────────────────────────────────────────────
    peers: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of VTEP peer addresses, usually the underlay IPs of the cluster nodes. Required for vxlan zones. Compared as an unordered set.',
    },
    vxlan_port: {
      type: 'Optional[Integer]',
      desc: 'UDP port for the VXLAN tunnel. Defaults to 4789.',
    },
    fabric: {
      type: 'Optional[String]',
      desc: 'SDN fabric used as the underlay for this zone. Fabrics themselves are not managed by this module; the name is passed through to PVE.',
    },

    # ── evpn ─────────────────────────────────────────────────────────────────
    controller: {
      type: 'Optional[String]',
      desc: 'EVPN controller for this zone (see pve_sdn_controller). Required for evpn zones.',
    },
    secondary_controllers: {
      type: 'Optional[Array[String]]',
      desc: 'Additional controllers for this zone. Compared as an unordered set.',
    },
    vrf_vxlan: {
      type: 'Optional[Integer]',
      desc: 'VNI of the zone VRF. Required for evpn zones, and must not collide with any VNet tag.',
    },
    exitnodes: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of nodes acting as EVPN exit nodes. Compared as an unordered set.',
    },
    exitnodes_local_routing: {
      type: 'Optional[Boolean]',
      desc: 'Allow exit nodes to reach EVPN guests locally.',
    },
    exitnodes_primary: {
      type: 'Optional[String]',
      desc: 'Force egress traffic through this exit node first.',
    },
    advertise_subnets: {
      type: 'Optional[Boolean]',
      desc: 'Advertise IP prefixes as EVPN type-5 routes instead of MAC/IP pairs as type-2 routes.',
    },
    disable_arp_nd_suppression: {
      type: 'Optional[Boolean]',
      desc: 'Stop suppressing IPv4 ARP and IPv6 neighbour discovery messages.',
    },
    rt_import: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of route targets to import into the zone VRF. Compared as an unordered set.',
    },
    mac: {
      type: 'Optional[String]',
      desc: 'Anycast MAC address of the logical router.',
    },

    # ── vxlan, evpn and qinq ─────────────────────────────────────────────────
    bridge_disable_mac_learning: {
      type: 'Optional[Boolean]',
      desc: 'Disable automatic MAC learning on the zone bridge.',
    },

    # ── faucet ───────────────────────────────────────────────────────────────
    dp_id: {
      type: 'Optional[Integer]',
      desc: 'Faucet dataplane ID. Only meaningful for the experimental faucet plugin.',
    },

    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_sdn_zone)
Puppet::Type::PveSensitiveParameters.register(:pve_sdn_zone)
Puppet::Type::PveSdnApplyAutobefore.register(:pve_sdn_zone)

# A zone referencing a controller, IPAM or DNS backend must be applied after it.
Puppet::Type.type(:pve_sdn_zone).autorequire(:pve_sdn_controller) do
  ([self[:controller]] + Array(self[:secondary_controllers])).compact
end

Puppet::Type.type(:pve_sdn_zone).autorequire(:pve_sdn_ipam) do
  [self[:ipam]].compact
end

Puppet::Type.type(:pve_sdn_zone).autorequire(:pve_sdn_dns) do
  [self[:dns], self[:reversedns]].compact
end
