# @summary Declares PVE resources from Hiera data.
#
# Include this class after `proxmox_virtual_environment` when adopting an existing
# PVE node or when you prefer data-driven resource declarations.
#
# @param storages
#   Hash of `pve_storage` resources, keyed by storage name.
# @param users
#   Hash of `pve_user` resources, keyed by user ID.
# @param acls
#   Hash of `pve_acl` resources, keyed as `path|ugid|role`.
# @param backup_jobs
#   Hash of `pve_backup_job` resources, keyed by job ID.
# @param notification_targets
#   Hash of `pve_notification_target` resources, keyed by target name.
# @param notification_matchers
#   Hash of `pve_notification_matcher` resources, keyed by matcher name.
# @param api_tokens
#   Hash of `pve_api_token` resources, keyed by full token ID (user@realm!tokenname).
# @param realms
#   Hash of `pve_realm` resources, keyed by realm name.
# @param node_config
#   Hash of `pve_node_config` resources, keyed by the actual PVE node name.
# @param pools
#   Hash of `pve_pool` resources, keyed by pool ID.
# @param roles
#   Hash of `pve_role` resources, keyed by role ID. Built-in (special) PVE roles cannot be managed.
# @param groups
#   Hash of `pve_group` resources, keyed by group ID.
# @param datacenter_config
#   Hash of `pve_datacenter_config` resources. PVE has exactly one cluster-wide
#   configuration; the only valid key is `datacenter`.
# @param ha_resources
#   Hash of `pve_ha_resource` resources, keyed by HA service ID including the
#   guest-type prefix, e.g. `vm:114`. Manages HA membership only -- never the
#   guest's own lifecycle.
# @param sdn_controllers
#   Hash of `pve_sdn_controller` resources, keyed by controller ID.
# @param sdn_ipams
#   Hash of `pve_sdn_ipam` resources, keyed by IPAM ID.
# @param sdn_dns
#   Hash of `pve_sdn_dns` resources, keyed by DNS backend ID.
# @param sdn_zones
#   Hash of `pve_sdn_zone` resources, keyed by zone ID.
# @param sdn_vnets
#   Hash of `pve_sdn_vnet` resources, keyed by VNet ID.
# @param sdn_subnets
#   Hash of `pve_sdn_subnet` resources, keyed as `vnet|cidr`.
# @param sdn_apply
#   Hash of `pve_sdn_apply` resources. PVE has exactly one SDN configuration;
#   the only valid key is `sdn`. Declaring this opts in to applying pending SDN
#   changes, which reloads networking on every cluster node. Leave it empty to
#   keep SDN changes pending, or set `noop: true` to report them without
#   applying. See the SDN section of the README.
#
# @example Declare resources from Hiera data
#   include proxmox_virtual_environment::resources
#
#   # hiera.yaml data:
#   # proxmox_virtual_environment::resources::storages:
#   #   backup-nfs:
#   #     type: nfs
#   #     server: nfs.example.com
#   #     nfs_export: /srv/pve-backups
#   #     content: backup
#
# @example Move a VXLAN zone to a new underlay, without applying it
#   include proxmox_virtual_environment::resources
#
#   # hiera.yaml data:
#   # proxmox_virtual_environment::resources::sdn_zones:
#   #   zone1:
#   #     type: vxlan
#   #     peers: '10.0.0.1,10.0.0.2,10.0.0.3'
#   #     mtu: 1450
#   # proxmox_virtual_environment::resources::sdn_vnets:
#   #   vnet1:
#   #     zone: zone1
#   #     vnet_tag: 10100
#   # proxmox_virtual_environment::resources::sdn_subnets:
#   #   'vnet1|10.0.0.0/24':
#   #     gateway: '10.0.0.1'
#   #     snat: true
#   #
#   # The zone rewrite above is pending only. Report it on every run without
#   # touching the network:
#   # proxmox_virtual_environment::resources::sdn_apply:
#   #   sdn:
#   #     noop: true
class proxmox_virtual_environment::resources (
  Hash[String, Hash] $storages              = {},
  Hash[String, Hash] $users                 = {},
  Hash[String, Hash] $acls                  = {},
  Hash[String, Hash] $backup_jobs           = {},
  Hash[String, Hash] $notification_targets   = {},
  Hash[String, Hash] $notification_matchers  = {},
  Hash[String, Hash] $api_tokens             = {},
  Hash[String, Hash] $realms                 = {},
  Hash[String, Hash] $node_config            = {},
  Hash[String, Hash] $pools                  = {},
  Hash[String, Hash] $roles                  = {},
  Hash[String, Hash] $groups                 = {},
  Hash[String, Hash] $datacenter_config      = {},
  Hash[String, Hash] $ha_resources           = {},
  Hash[String, Hash] $sdn_controllers        = {},
  Hash[String, Hash] $sdn_ipams              = {},
  Hash[String, Hash] $sdn_dns                = {},
  Hash[String, Hash] $sdn_zones              = {},
  Hash[String, Hash] $sdn_vnets              = {},
  Hash[String, Hash] $sdn_subnets            = {},
  Hash[String, Hash] $sdn_apply              = {},
) {
  $storages.each |String $title, Hash $attributes| {
    pve_storage { $title:
      * => $attributes,
    }
  }

  $users.each |String $title, Hash $attributes| {
    pve_user { $title:
      * => $attributes,
    }
  }

  $acls.each |String $title, Hash $attributes| {
    pve_acl { $title:
      * => $attributes,
    }
  }

  $backup_jobs.each |String $title, Hash $attributes| {
    pve_backup_job { $title:
      * => $attributes,
    }
  }

  $notification_targets.each |String $title, Hash $attributes| {
    pve_notification_target { $title:
      * => $attributes,
    }
  }

  $notification_matchers.each |String $title, Hash $attributes| {
    pve_notification_matcher { $title:
      * => $attributes,
    }
  }

  $api_tokens.each |String $title, Hash $attributes| {
    pve_api_token { $title:
      * => $attributes,
    }
  }

  $realms.each |String $title, Hash $attributes| {
    pve_realm { $title:
      * => $attributes,
    }
  }

  $node_config.each |String $title, Hash $attributes| {
    pve_node_config { $title:
      * => $attributes,
    }
  }

  $pools.each |String $title, Hash $attributes| {
    pve_pool { $title:
      * => $attributes,
    }
  }

  $roles.each |String $title, Hash $attributes| {
    pve_role { $title:
      * => $attributes,
    }
  }

  $groups.each |String $title, Hash $attributes| {
    pve_group { $title:
      * => $attributes,
    }
  }

  $datacenter_config.each |String $title, Hash $attributes| {
    pve_datacenter_config { $title:
      * => $attributes,
    }
  }

  $ha_resources.each |String $title, Hash $attributes| {
    pve_ha_resource { $title:
      * => $attributes,
    }
  }

  # ── SDN ────────────────────────────────────────────────────────────────────
  # Ordering (ipam/dns and controllers before zones, zones before vnets, vnets
  # before subnets, everything before the apply) comes from autorequires
  # declared on the types themselves, so it holds for hand-written manifests
  # too and is not repeated here.
  $sdn_controllers.each |String $title, Hash $attributes| {
    pve_sdn_controller { $title:
      * => $attributes,
    }
  }

  $sdn_ipams.each |String $title, Hash $attributes| {
    pve_sdn_ipam { $title:
      * => $attributes,
    }
  }

  $sdn_dns.each |String $title, Hash $attributes| {
    pve_sdn_dns { $title:
      * => $attributes,
    }
  }

  $sdn_zones.each |String $title, Hash $attributes| {
    pve_sdn_zone { $title:
      * => $attributes,
    }
  }

  $sdn_vnets.each |String $title, Hash $attributes| {
    pve_sdn_vnet { $title:
      * => $attributes,
    }
  }

  $sdn_subnets.each |String $title, Hash $attributes| {
    pve_sdn_subnet { $title:
      * => $attributes,
    }
  }

  $sdn_apply.each |String $title, Hash $attributes| {
    pve_sdn_apply { $title:
      * => $attributes,
    }
  }

  # Order related resources only when both are managed by this Hiera class.
  $users.each |String $title, Hash $attributes| {
    $realm = $title.split('@')[-1]
    if $realm in $realms {
      Pve_realm[$realm] -> Pve_user[$title]
    }

    if $attributes['groups'] {
      $attributes['groups'].split(',').each |String $group| {
        if $group in $groups {
          Pve_group[$group] -> Pve_user[$title]
        }
      }
    }
  }

  $api_tokens.each |String $title, Hash $attributes| {
    $userid = $title.split('!')[0]
    if $userid in $users {
      Pve_user[$userid] -> Pve_api_token[$title]
    }
  }

  $acls.each |String $title, Hash $attributes| {
    $parts = $title.split('[|]')
    $ugid = $parts[1]
    $role = $parts[2]
    $group = regsubst($ugid, '^@', '')

    if $ugid in $users {
      Pve_user[$ugid] -> Pve_acl[$title]
    }
    if $group in $groups {
      Pve_group[$group] -> Pve_acl[$title]
    }
    if $ugid in $api_tokens {
      Pve_api_token[$ugid] -> Pve_acl[$title]
    }
    if $role in $roles {
      Pve_role[$role] -> Pve_acl[$title]
    }
  }

  $backup_jobs.each |String $title, Hash $attributes| {
    $storage = $attributes['storage']
    $pool = $attributes['pool']

    if $storage and $storage in $storages {
      Pve_storage[$storage] -> Pve_backup_job[$title]
    }
    if $pool and $pool in $pools {
      Pve_pool[$pool] -> Pve_backup_job[$title]
    }
  }

  $notification_matchers.each |String $title, Hash $attributes| {
    if $attributes['target'] {
      $attributes['target'].each |String $target| {
        if $target in $notification_targets {
          Pve_notification_target[$target] -> Pve_notification_matcher[$title]
        }
      }
    }
  }
}
