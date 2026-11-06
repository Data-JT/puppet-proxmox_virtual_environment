# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'pve_notification_target',
  docs:  'Manages a Proxmox Virtual Environment notification target (sendmail, smtp, gotify, or webhook).',
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this notification target should exist.',
      default: 'present',
    },
    name: {
      type:      'String',
      desc:      'The notification target name.',
      behaviour: :namevar,
    },
    type: {
      type: 'Enum[sendmail, smtp, gotify, webhook]',
      desc: 'Target type. Determines the delivery mechanism. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    disable: {
      type: 'Optional[Boolean]',
      desc: 'Disable this notification target.',
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    # Sendmail and SMTP
    author: {
      type: 'Optional[String]',
      desc: 'Author name shown in sent emails.',
    },
    from_address: {
      type: 'Optional[String]',
      desc: 'From address for sent emails. Required for smtp targets.',
    },
    mailto: {
      type: 'Optional[Array[String]]',
      desc: 'List of email addresses to notify.',
    },
    mailto_user: {
      type: 'Optional[Array[String]]',
      desc: 'List of PVE user IDs whose configured email addresses receive notifications.',
    },
    # SMTP and Gotify share the server field
    server: {
      type: 'Optional[String]',
      desc: 'SMTP relay hostname/IP (smtp) or Gotify server URL (gotify).',
    },
    # SMTP-specific
    port: {
      type: 'Optional[Integer]',
      desc: 'SMTP port. Defaults to 25 (insecure), 465 (tls), or 587 (starttls).',
    },
    mode: {
      type: 'Optional[Enum[insecure, starttls, tls]]',
      desc: 'SMTP TLS mode. Defaults to tls.',
    },
    username: {
      type: 'Optional[String]',
      desc: 'SMTP authentication username.',
    },
    smtp_password: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'SMTP authentication password. PVE never returns it, so it is compared against /etc/pve/priv/notifications.cfg; requires the agent to run on the PVE node as root.',
      sensitive: true,
    },
    # Gotify-specific
    token: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'Gotify authentication token. PVE never returns it, so it is compared against /etc/pve/priv/notifications.cfg; requires the agent to run on the PVE node as root.',
      sensitive: true,
    },
    # Webhook-specific
    url: {
      type: 'Optional[String]',
      desc: 'Webhook URL. Required for webhook targets.',
    },
    http_method: {
      type: 'Optional[Enum[post, put, get]]',
      desc: 'HTTP method for webhook requests. Defaults to post.',
    },
    body: {
      type: 'Optional[String]',
      desc: 'Plain webhook request body template. The provider base64-encodes it for PVE.',
    },
    header: {
      type: 'Optional[Array[Hash]]',
      desc: 'Webhook HTTP headers as hashes with "name" and "value" keys. Values are base64-encoded for PVE.',
    },
    secret: {
      type:      'Optional[Array[Hash]]',
      desc:      'Webhook secrets as hashes with "name" and optional "value" keys, base64-encoded for PVE. Compared as an unordered name/value set read from /etc/pve/priv/notifications.cfg.',
      sensitive: true,
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_notification_target)
Puppet::Type::PveSensitiveParameters.register(:pve_notification_target)
