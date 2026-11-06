# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'
require_relative 'pve_sdn_apply_autobefore'

Puppet::ResourceApi.register_type(
  name:     'pve_sdn_vnet',
  docs:     <<~DOCS,
    Manages a Proxmox Virtual Environment SDN VNet.

    **This resource writes pending configuration only.** A change here lands in
    /etc/pve/sdn/vnets.cfg and alters nothing on the wire until the separate
    `PUT /cluster/sdn` apply runs. This type never performs that apply; declare
    `pve_sdn_apply` to opt in, or `pve_sdn_apply { 'sdn': noop => true }` to have
    every run report unapplied changes without touching the network.
  DOCS
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this SDN VNet should exist.',
      default: 'present',
    },
    vnet: {
      type:      'String[1,8]',
      desc:      'The SDN VNet identifier. PVE limits this to 8 characters.',
      behaviour: :namevar,
    },
    type: {
      type:      "Optional[Enum['vnet']]",
      desc:      'Object type. PVE only defines "vnet" here; it exists for symmetry with the other SDN types and cannot be changed after creation.',
      behaviour: :init_only,
    },
    pending_state: {
      type:      "Optional[Enum['new', 'changed', 'deleted']]",
      desc:      'Read-only. Whether this VNet differs from the applied running configuration. Absent means the VNet is applied.',
      behaviour: :read_only,
    },
    zone: {
      type: 'String',
      desc: 'Zone this VNet belongs to. PVE permits moving a VNet between zones, so this is an ordinary property rather than an immutable one.',
    },
    vnet_tag: {
      type: 'Optional[Integer]',
      desc: "VLAN tag for vlan and qinq zones, or the VXLAN VNI for vxlan and evpn zones. Maps to PVE's `tag`; Puppet reserves that name as a metaparameter.",
    },
    vnet_alias: {
      type: 'Optional[String]',
      desc: "Human-readable alias for this VNet. Maps to PVE's `alias`; Puppet reserves that name as a metaparameter.",
    },
    vlanaware: {
      type: 'Optional[Boolean]',
      desc: 'Allow VLAN-tagged traffic to pass through this VNet.',
    },
    isolate_ports: {
      type: 'Optional[Boolean]',
      desc: 'Set the isolated flag on every interface attached to this VNet bridge, preventing guest-to-guest traffic within the VNet.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_sdn_vnet)
Puppet::Type::PveSensitiveParameters.register(:pve_sdn_vnet)
Puppet::Type::PveSdnApplyAutobefore.register(:pve_sdn_vnet)

# A VNet cannot be created before the zone it belongs to.
Puppet::Type.type(:pve_sdn_vnet).autorequire(:pve_sdn_zone) do
  [self[:zone]].compact
end
