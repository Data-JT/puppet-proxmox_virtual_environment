# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name: 'pve_backup_job',
  docs: 'Manages a scheduled Proxmox Virtual Environment vzdump backup job.',
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type: 'Enum[present, absent]',
      desc: 'Whether this backup job should exist.',
      default: 'present',
    },
    id: {
      type: 'String',
      desc: 'Unique backup job ID.',
      behaviour: :namevar,
    },
    enabled: {
      type: 'Optional[Boolean]',
      desc: 'Whether this backup job is enabled.',
    },
    job_schedule: {
      type: 'Optional[String]',
      desc: 'Calendar event schedule. Named job_schedule because schedule is reserved by Puppet.',
    },
    storage: {
      type: 'Optional[String]',
      desc: 'Target storage ID.',
    },
    mode: {
      type: "Optional[Enum['snapshot', 'suspend', 'stop']]",
      desc: 'Backup mode.',
    },
    all: {
      type: 'Optional[Boolean]',
      desc: 'Back up all guests.',
    },
    vmid: {
      type: 'Optional[Variant[String, Array[Variant[String, Integer]]]]',
      desc: 'Guest IDs to include — either a comma-separated String (PVE property-string format) or an Array of IDs, which is joined into the property-string form before being sent to the API.',
    },
    exclude: {
      type: 'Optional[Variant[String, Array[Variant[String, Integer]]]]',
      desc: 'Guest IDs to exclude — either a comma-separated String (PVE property-string format) or an Array of IDs, which is joined into the property-string form before being sent to the API.',
    },
    node: {
      type: 'Optional[String]',
      desc: 'Restrict the job to one cluster node.',
    },
    pool: {
      type: 'Optional[String]',
      desc: 'Restrict the job to a resource pool.',
    },
    compress: {
      type: 'Optional[String]',
      desc: 'Compression algorithm.',
    },
    prune_backups: {
      type: 'Optional[String]',
      desc: 'Retention options in PVE property-string format.',
    },
    mailto: {
      type: 'Optional[String]',
      desc: 'Notification email recipients.',
    },
    mailnotification: {
      type: "Optional[Enum['always', 'failure']]",
      desc: 'When to send legacy email notifications.',
    },
    notification_mode: {
      type: "Optional[Enum['auto', 'legacy-sendmail', 'notification-system']]",
      desc: 'Notification delivery mode.',
    },
    notes_template: {
      type: 'Optional[String]',
      desc: 'Template used for backup notes.',
    },
    protected: {
      type: 'Optional[Boolean]',
      desc: 'Mark created backups as protected.',
    },
    repeat_missed: {
      type: 'Optional[Boolean]',
      desc: 'Run missed jobs when the node becomes available.',
    },
    bwlimit: {
      type: 'Optional[Integer]',
      desc: 'I/O bandwidth limit in KiB/s.',
    },
    fleecing: {
      type: 'Optional[String]',
      desc: 'Backup fleecing options in PVE property-string format (e.g. "enabled=1,storage=local-lvm"). VM only.',
    },
    performance: {
      type: 'Optional[String]',
      desc: 'Performance-related settings in PVE property-string format (e.g. "max-workers=2,pbs-entries-max=1024").',
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

Puppet::Type::PveTransportAutorequire.register(:pve_backup_job)
Puppet::Type::PveSensitiveParameters.register(:pve_backup_job)
