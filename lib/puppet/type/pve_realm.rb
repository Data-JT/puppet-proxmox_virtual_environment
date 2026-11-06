# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pve_transport_autorequire'
require_relative 'pve_sensitive_parameters'

Puppet::ResourceApi.register_type(
  name:  'pve_realm',
  docs:  'Manages a Proxmox Virtual Environment authentication realm.',
  features: ['custom_insync'],

  attributes: {
    ensure: {
      type:    'Enum[present, absent]',
      desc:    'Whether this realm should exist.',
      default: 'present',
    },
    realm: {
      type:      'String',
      desc:      'The realm identifier.',
      behaviour: :namevar,
    },
    type: {
      type: "Enum['pam', 'pve', 'ldap', 'ad', 'openid']",
      desc: 'Realm type. Cannot be changed after creation.',
      behaviour: :init_only,
    },
    comment: {
      type: 'Optional[String]',
      desc: 'Optional human-readable comment.',
    },
    default: {
      type: 'Optional[Boolean]',
      desc: 'Set this realm as the default login realm.',
    },

    # ── LDAP and AD ─────────────────────────────────────────────────────────
    server1: {
      type: 'Optional[String]',
      desc: 'Primary LDAP/AD server hostname or IP. Required for ldap and ad realms.',
    },
    server2: {
      type: 'Optional[String]',
      desc: 'Fallback LDAP/AD server hostname or IP.',
    },
    port: {
      type: 'Optional[Integer]',
      desc: 'LDAP/AD server port.',
    },
    domain: {
      type: 'Optional[String]',
      desc: 'AD domain name (e.g. example.com). Required for ad realms.',
    },
    bind_dn: {
      type: 'Optional[String]',
      desc: 'DN used to bind for searches (e.g. cn=search,dc=example,dc=com).',
    },
    bind_password: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'Password for the bind DN. PVE never returns it, so it is compared against /etc/pve/priv/realm/<realm>.pw; requires the agent to run on the PVE node as root.',
      sensitive: true,
    },
    mode: {
      type: "Optional[Enum['ldap', 'ldap+starttls', 'ldaps']]",
      desc: 'Connection security mode. Defaults to ldap.',
    },
    verify: {
      type: 'Optional[Boolean]',
      desc: 'Verify the server TLS certificate.',
    },
    secure: {
      type: 'Optional[Boolean]',
      desc: 'Use secure LDAPS protocol. Deprecated by PVE in favor of mode.',
    },
    sslversion: {
      type: "Optional[Enum['tlsv1', 'tlsv1_1', 'tlsv1_2', 'tlsv1_3']]",
      desc: 'LDAPS TLS/SSL version to use.',
    },
    capath: {
      type: 'Optional[String]',
      desc: 'CA certificate or directory path for TLS verification.',
    },
    cert: {
      type: 'Optional[String]',
      desc: 'Path to the client certificate for TLS client authentication.',
    },
    certkey: {
      type: 'Optional[String]',
      desc: 'Path to the client certificate key for TLS client authentication.',
    },
    case_sensitive: {
      type: 'Optional[Boolean]',
      desc: 'Whether usernames are treated as case-sensitive. Defaults to true.',
    },
    filter: {
      type: 'Optional[String]',
      desc: 'LDAP filter restricting which objects are considered users.',
    },
    sync_defaults_options: {
      type: 'Optional[String]',
      desc: 'Default options for realm sync (e.g. scope=subtree).',
    },
    sync_attributes: {
      type: 'Optional[String]',
      desc: 'Attribute mapping for user sync (e.g. email=mail,firstname=givenName).',
    },
    user_classes: {
      type: 'Optional[String]',
      desc: 'Comma-separated LDAP object classes treated as user accounts.',
    },
    tfa: {
      type: 'Optional[String]',
      desc: 'Two-factor authentication configuration in PVE property-string format (e.g. type=oath,digits=6).',
    },

    # ── LDAP-specific ────────────────────────────────────────────────────────
    base_dn: {
      type: 'Optional[String]',
      desc: 'Base DN for user searches. Required for ldap; auto-detected for ad.',
    },
    user_attr: {
      type: 'Optional[String]',
      desc: 'LDAP attribute that holds the username (e.g. uid, sAMAccountName). Required for ldap.',
    },

    # ── LDAP/AD group sync ───────────────────────────────────────────────────
    group_dn: {
      type: 'Optional[String]',
      desc: 'LDAP base DN for group sync. Defaults to base_dn when unset.',
    },
    group_filter: {
      type: 'Optional[String]',
      desc: 'LDAP filter restricting which objects are considered groups during sync.',
    },
    group_classes: {
      type: 'Optional[String]',
      desc: 'Comma-separated LDAP object classes treated as groups during sync.',
    },
    group_name_attr: {
      type: 'Optional[String]',
      desc: 'LDAP attribute used as a group name. Falls back to the first DN component when unset.',
    },

    # ── OpenID Connect ───────────────────────────────────────────────────────
    issuer_url: {
      type: 'Optional[String]',
      desc: 'OpenID provider issuer URL. Required for openid realms.',
    },
    client_id: {
      type: 'Optional[String]',
      desc: 'OAuth2 client ID registered with the provider. Required for openid realms.',
    },
    client_key: {
      type:      'Optional[Variant[String, Sensitive[String]]]',
      desc:      'OAuth2 client secret. PVE stores this in cleartext in /etc/pve/domains.cfg and returns it from the API, so it is compared directly like any other property.',
      sensitive: true,
    },
    username_claim: {
      type: 'Optional[String]',
      behaviour: :init_only,
      desc: 'JWT claim used as the PVE username (e.g. email, sub). Cannot be changed after creation.',
    },
    autocreate: {
      type: 'Optional[Boolean]',
      desc: 'Automatically create PVE users on first successful OpenID login.',
    },
    scopes: {
      type: 'Optional[String]',
      desc: 'Space-separated list of OAuth2 scopes to request.',
    },
    prompt: {
      type: 'Optional[String]',
      desc: 'OpenID prompt parameter (e.g. login, consent).',
    },
    acr_values: {
      type: 'Optional[String]',
      desc: 'Space-separated Authentication Context Class References.',
    },
    audiences: {
      type: 'Optional[String]',
      desc: 'Space-separated list of accepted token audiences.',
    },
    query_userinfo: {
      type: 'Optional[Boolean]',
      desc: 'Query the OpenID userinfo endpoint for additional claims. Defaults to true.',
    },
    groups_claim: {
      type: 'Optional[String]',
      desc: "OpenID claim used to retrieve a user's groups.",
    },
    groups_autocreate: {
      type: 'Optional[Boolean]',
      desc: 'Automatically create PVE groups from the groups claim if they do not exist.',
    },
    groups_overwrite: {
      type: 'Optional[Boolean]',
      desc: "Overwrite all of a user's group memberships with the groups claim on every login.",
    },
    delete_properties: {
      type: 'Optional[Array[String]]',
      desc: 'PVE API property names to remove during an update.',
    },
  },
)

Puppet::Type::PveTransportAutorequire.register(:pve_realm)
Puppet::Type::PveSensitiveParameters.register(:pve_realm)
