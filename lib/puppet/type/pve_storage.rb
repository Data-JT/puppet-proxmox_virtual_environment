# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name: 'pve_storage',
  docs: 'Manages a Proxmox Virtual Environment storage definition.',
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type: 'Enum[present, absent]',
      desc: 'Whether this storage definition should exist.',
      default: 'present',
    },
    storage: {
      type: 'String',
      desc: 'The PVE storage ID.',
      behaviour: :namevar,
    },
    type: {
      type: "Enum['btrfs', 'cephfs', 'cifs', 'dir', 'esxi', 'iscsi', 'iscsidirect', 'lvm', 'lvmthin', 'nfs', 'pbs', 'rbd', 'zfs', 'zfspool']",
      desc: 'Storage backend type. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    content: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of allowed content types.',
    },
    path: {
      type: 'Optional[String]',
      desc: 'Filesystem path for directory-like storage backends. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    server: {
      type: 'Optional[String]',
      desc: 'Remote server for network storage. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    nfs_export: {
      type: 'Optional[String]',
      desc: 'NFS export path. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    share: {
      type: 'Optional[String]',
      desc: 'CIFS share name. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    portal: {
      type: 'Optional[String]',
      desc: 'iSCSI portal. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    target: {
      type: 'Optional[String]',
      desc: 'iSCSI target. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    vgname: {
      type: 'Optional[String]',
      desc: 'LVM volume group name. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    thinpool: {
      type: 'Optional[String]',
      desc: 'LVM thin pool name. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    pool: {
      type: 'Optional[String]',
      desc: 'Ceph or ZFS pool name. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    data_pool: {
      type: 'Optional[String]',
      desc: 'Ceph data pool used for erasure coding.',
    },
    monhost: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of Ceph monitor IP addresses (for external clusters).',
    },
    keyring: {
      type: 'Optional[String]',
      desc: 'Ceph client keyring contents (for external clusters).',
    },
    krbd: {
      type: 'Optional[Boolean]',
      desc: 'Always access RBD storage through the krbd kernel module.',
    },
    datastore: {
      type: 'Optional[String]',
      desc: 'Proxmox Backup Server datastore name. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    encryption_key: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'Encryption key for PBS storages as a JSON string, or "autogen" to generate one. Compared by the key fingerprint PVE reports; "autogen" only requires that some key exists.',
      sensitive: true,
    },
    username: {
      type: 'Optional[String]',
      desc: 'Remote storage username.',
    },
    password: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'Remote storage password. PVE never returns it, so it is compared against /etc/pve/priv/storage/<id>.pw; requires the agent to run on the PVE node as root.',
      sensitive: true,
    },
    nodes: {
      type: 'Optional[String]',
      desc: 'Comma-separated list of nodes allowed to use this storage.',
    },
    disable: {
      type: 'Optional[Boolean]',
      desc: 'Disable this storage.',
    },
    shared: {
      type: 'Optional[Boolean]',
      desc: 'Mark this storage as shared between nodes.',
    },
    prune_backups: {
      type: 'Optional[String]',
      desc: 'Backup retention options in PVE property-string format.',
    },
    max_protected_backups: {
      type: 'Optional[Integer]',
      desc: 'Maximum number of protected backups per guest.',
    },
    namespace: {
      type: 'Optional[String]',
      desc: 'Proxmox Backup Server namespace.',
    },
    fingerprint: {
      type: 'Optional[String]',
      desc: 'Remote TLS certificate fingerprint.',
    },
    skip_cert_verification: {
      type: 'Optional[Boolean]',
      desc: 'Skip remote TLS certificate verification.',
    },
    options: {
      type: 'Optional[String]',
      desc: 'Backend-specific mount options.',
    },
    mountpoint: {
      type: 'Optional[String]',
      desc: 'Mount point for applicable storage backends.',
    },
    subdir: {
      type: 'Optional[String]',
      desc: 'Subdirectory to use on the backend.',
    },
    is_mountpoint: {
      type: 'Optional[String]',
      desc: 'Path PVE should treat as an externally managed mountpoint, or "yes"/"no" to use the storage path as a shortcut.',
    },
    create_base_path: {
      type: 'Optional[Boolean]',
      desc: 'Create the base directory if it does not exist. Defaults to true.',
    },
    create_subdirs: {
      type: 'Optional[Boolean]',
      desc: 'Populate the directory with the default content-type subdirectory structure. Defaults to true.',
    },
    bwlimit: {
      type: 'Optional[String]',
      desc: 'I/O bandwidth limits in PVE property-string format (e.g. "restore=10240,migration=5120"), in KiB/s.',
    },
    blocksize: {
      type: 'Optional[String]',
      desc: 'ZFS block size (a power of 2, optionally suffixed with k or m). Cannot be changed after creation.',
      behaviour: :init_only,
    },
    preallocation: {
      type: "Optional[Enum['off', 'metadata', 'falloc', 'full']]",
      desc: 'Preallocation mode for raw and qcow2 images. Defaults to metadata.',
    },
    sparse: {
      type: 'Optional[Boolean]',
      desc: 'Use sparse volumes.',
    },
    nocow: {
      type: 'Optional[Boolean]',
      desc: 'Set the NOCOW flag on files, disabling data checksumming. Only use on storage that is otherwise protected against bitrot.',
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_storage)
Puppet::Type::PveSensitiveParameters.register(:pve_storage)
