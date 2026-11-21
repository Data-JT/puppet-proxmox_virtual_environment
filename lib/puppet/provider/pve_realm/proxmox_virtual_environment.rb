# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveRealm; end

# Provider for pve_realm resources via the PVE REST API.
#
class Puppet::Provider::PveRealm::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  # PVE's login code reads `username-claim` with a fallback of "sub"
  # (API2/OpenId.pm), so a realm stored without one behaves exactly like one
  # stored with "sub". get reports it that way, or declaring the default on
  # such a realm would read as a change to a create-only attribute.
  DEFAULT_USERNAME_CLAIM = 'sub' unless const_defined?(:DEFAULT_USERNAME_CLAIM)

  def self.attribute_map
    {
      'realm'                 => :realm,
      'type'                  => :type,
      'comment'               => :comment,
      'default'               => :default,
      # LDAP / AD
      'server1'               => :server1,
      'server2'               => :server2,
      'port'                  => :port,
      'domain'                => :domain,
      'bind_dn'               => :bind_dn,
      'password'              => :bind_password,
      'mode'                  => :mode,
      'verify'                => :verify,
      'secure'                => :secure,
      'sslversion'            => :sslversion,
      'capath'                => :capath,
      'cert'                  => :cert,
      'certkey'               => :certkey,
      'case-sensitive'        => :case_sensitive,
      'filter'                => :filter,
      'sync-defaults-options' => :sync_defaults_options,
      'sync_attributes'       => :sync_attributes,
      'user_classes'          => :user_classes,
      'tfa'                   => :tfa,
      # LDAP-only
      'base_dn'               => :base_dn,
      'user_attr'             => :user_attr,
      # LDAP / AD group sync
      'group_dn'              => :group_dn,
      'group_filter'          => :group_filter,
      'group_classes'         => :group_classes,
      'group_name_attr'       => :group_name_attr,
      # OpenID
      'issuer-url'            => :issuer_url,
      'client-id'             => :client_id,
      'client-key'            => :client_key,
      'username-claim'        => :username_claim,
      'autocreate'            => :autocreate,
      'scopes'                => :scopes,
      'prompt'                => :prompt,
      'acr-values'            => :acr_values,
      'audiences'             => :audiences,
      'query-userinfo'        => :query_userinfo,
      'groups-claim'          => :groups_claim,
      'groups-autocreate'     => :groups_autocreate,
      'groups-overwrite'      => :groups_overwrite,
      'delete'                => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:default, :verify, :secure, :case_sensitive, :autocreate, :query_userinfo, :groups_autocreate, :groups_overwrite]
  end

  # From the `options` of each realm plugin in pve-access-control
  # (src/PVE/Auth/{PAM,PVE,LDAP,AD,OpenId}.pm). The API schema merges all
  # types into one, so it cannot tell them apart.
  def self.attributes_by_type
    ldap = [:base_dn, :bind_dn, :bind_password, :capath, :case_sensitive, :cert, :certkey, :default, :filter,
            :group_classes, :group_dn, :group_filter, :group_name_attr, :mode, :port, :secure, :server1, :server2,
            :sslversion, :sync_attributes, :sync_defaults_options, :tfa, :user_attr, :user_classes, :verify]
    {
      'pam'    => [:default, :tfa],
      'pve'    => [:default, :tfa],
      'ldap'   => ldap,
      'ad'     => ldap + [:domain],
      'openid' => [:acr_values, :audiences, :autocreate, :client_id, :client_key, :default, :groups_autocreate,
                   :groups_claim, :groups_overwrite, :issuer_url, :prompt, :query_userinfo, :scopes, :username_claim],
    }
  end

  # client_key is deliberately absent: Auth/OpenId.pm:110 declares it an
  # ordinary realm option and API2/Domains.pm never special-cases it, so PVE
  # keeps it in the public domains.cfg and returns it verbatim. It needs no
  # store lookup and no custom comparison at all.
  def self.secret_attributes
    [:bind_password]
  end

  def stored_secret(title, attribute_name)
    return nil unless attribute_name == :bind_password

    PuppetX::ProxmoxVirtualEnvironment::SecretStore.realm_password(title)
  end

  def get(context)
    # Non-raising probe; see pve_storage#get for why discovery must not fail
    # closed here.
    store_available = PuppetX::ProxmoxVirtualEnvironment::SecretStore.available?
    (transport_get(context, '/access/domains') || []).map do |summary|
      name = summary['realm']
      details = transport_get(context, "/access/domains/#{name}") || {}
      puppet_realm = pve_to_puppet(details).merge(realm: name, ensure: 'present')
      puppet_realm[:username_claim] ||= DEFAULT_USERNAME_CLAIM if puppet_realm[:type] == 'openid'
      puppet_realm[:bind_password] = SECRET_PLACEHOLDER if store_available && stored_bind_password?(name)
      puppet_realm
    end
  end

  def create(context, name, should)
    context.notice("Creating #{should[:type]} realm '#{name}'")
    pve_transport(context).post(context, '/access/domains', create_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating #{should[:type]} realm '#{name}'")
    body = without_create_only(context, should)
    pve_transport(context).put(context, "/access/domains/#{name}", update_body(context, body))
  end

  def delete(context, name)
    context.notice("Deleting realm '#{name}'")
    pve_transport(context).delete(context, "/access/domains/#{name}")
  end

  private

  def stored_bind_password?(realm)
    !PuppetX::ProxmoxVirtualEnvironment::SecretStore.realm_password(realm).nil?
  end
end
