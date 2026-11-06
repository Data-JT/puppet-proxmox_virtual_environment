# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'
require_relative 'pve_sdn_apply_autobefore'

Puppet::ResourceApi.register_type(
  name:     'pve_sdn_subnet',
  docs:     <<~DOCS,
    Manages a Proxmox Virtual Environment SDN subnet.

    **This resource writes pending configuration only.** A change here lands in
    /etc/pve/sdn/subnets.cfg and alters nothing on the wire until the separate
    `PUT /cluster/sdn` apply runs. This type never performs that apply; declare
    `pve_sdn_apply` to opt in, or `pve_sdn_apply { 'sdn': noop => true }` to have
    every run report unapplied changes without touching the network.

    ### Identity

    Subnets are nested under a VNet, and PVE does not use the CIDR as the object
    identifier. It derives one by prefixing the VNet's zone and replacing the
    slash with a dash, so `10.0.0.0/24` in a VNet belonging to zone `zone1`
    becomes `zone1-10.0.0.0-24`. Only the create endpoint accepts a bare CIDR;
    update and delete address the derived identifier.

    This type is therefore keyed by VNet and CIDR, written as a pipe-separated
    title in the same style as `pve_acl`. The provider resolves the VNet's zone
    and derives the PVE identifier itself, and reports it back in the read-only
    `subnet_id` property.

    ```puppet
    pve_sdn_subnet { 'vnet1|10.0.0.0/24':
      gateway => '10.0.0.1',
      snat    => true,
    }
    ```

    Changing the CIDR of an existing subnet is a delete and a create, not an
    update: the CIDR is part of the identity.
  DOCS
  features: ['custom_insync'],

  title_patterns: [
    {
      pattern: %r{^(?<vnet>[^|]+)\|(?<cidr>.+)$},
      desc:    'Where the VNet and the subnet CIDR are provided with a pipe separator',
    },
    {
      pattern: %r{^(?<vnet>.+)$},
      desc:    'Where only the VNet is provided (requires the cidr param)',
    },
  ],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this SDN subnet should exist.',
      default: 'present',
    },
    vnet: {
      type:      'String[1,8]',
      desc:      'VNet this subnet belongs to.',
      behaviour: :namevar,
    },
    cidr: {
      type:      'String',
      desc:      'Subnet in CIDR notation, e.g. 10.0.0.0/24. Part of the identity: changing it replaces the subnet.',
      behaviour: :namevar,
    },
    type: {
      type:      "Optional[Enum['subnet']]",
      desc:      'Object type. PVE only defines "subnet" here. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    subnet_id: {
      type:      'Optional[String]',
      desc:      'Read-only. The identifier PVE derived for this subnet, e.g. zone1-10.0.0.0-24.',
      behaviour: :read_only,
    },
    pending_state: {
      type:      "Optional[Enum['new', 'changed', 'deleted']]",
      desc:      'Read-only. Whether this subnet differs from the applied running configuration. Absent means the subnet is applied.',
      behaviour: :read_only,
    },
    gateway: {
      type: 'Optional[String]',
      desc: 'Gateway address for this subnet. Assigned to the VNet interface in layer 3 zones.',
    },
    snat: {
      type: 'Optional[Boolean]',
      desc: 'Masquerade traffic leaving this subnet. Requires the PVE firewall.',
    },
    dnszoneprefix: {
      type: 'Optional[String]',
      desc: "DNS prefix inserted before the zone's domain, e.g. 'adm' yields <hostname>.adm.example.com.",
    },
    dhcp_range: {
      type: 'Optional[Array[String]]',
      desc: "DHCP ranges as PVE property strings, e.g. 'start-address=10.0.0.100,end-address=10.0.0.200'. PVE returns them expanded and reordered, so they compare as an unordered set.",
    },
    dhcp_dns_server: {
      type: 'Optional[String]',
      desc: 'DNS server address handed out to DHCP clients in this subnet.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_sdn_subnet)
Puppet::Type::PveSensitiveParameters.register(:pve_sdn_subnet)
Puppet::Type::PveSdnApplyAutobefore.register(:pve_sdn_subnet)

# A subnet cannot be created before the VNet that contains it.
Puppet::Type.type(:pve_sdn_subnet).autorequire(:pve_sdn_vnet) do
  [self[:vnet]].compact
end
