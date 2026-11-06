# frozen_string_literal: true

require_relative '../pve_base_provider'
require_relative '../../../puppet_x/proxmox_virtual_environment/crypt' # see config.rb: bare require breaks in puppetserver
require_relative '../../../puppet_x/proxmox_virtual_environment/pveum' # ditto

# @api private
module Puppet::Provider::PveUser; end

# Provider for pve_user resources via the PVE REST API.
class Puppet::Provider::PveUser::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'userid'    => :userid,
      'comment'   => :comment,
      'email'     => :email,
      'enable'    => :enable,
      'expire'    => :expire,
      'firstname' => :firstname,
      'groups'    => :groups,
      'keys'      => :keys,
      'lastname'  => :lastname,
    }
  end

  def self.boolean_attributes
    [:enable]
  end

  # PVE returns the comma-separated group list in its own canonical order
  # regardless of the order it was declared or sent in; compare groups as an
  # unordered set so runs converge instead of re-sending the declared order.
  def insync?(context, name, attribute_name, is, should)
    return unordered_csv_insync?(is[:groups], should[:groups]) if attribute_name == :groups

    super
  end

  def self.secret_attributes
    [:password]
  end

  def stored_secret(title, attribute_name)
    return nil unless attribute_name == :password

    PuppetX::ProxmoxVirtualEnvironment::SecretStore.user_password_hash(title)
  end

  # The only secret PVE stores hashed rather than in plaintext.
  def secret_matches?(stored, desired)
    PuppetX::ProxmoxVirtualEnvironment::Crypt.verify(desired, stored)
  end

  def get(context)
    # Non-raising probe; see pve_storage#get for why discovery must not fail
    # closed here.
    store_available = PuppetX::ProxmoxVirtualEnvironment::SecretStore.available?
    (transport_get(context, '/access/users') || []).map do |user|
      puppet_user = pve_to_puppet(user).merge(ensure: 'present')
      puppet_user[:password] = SECRET_PLACEHOLDER if store_available && stored_password?(puppet_user[:userid])
      puppet_user
    end
  end

  def create(context, name, should)
    validate_userid!(name)
    context.notice("Creating user '#{name}'")
    body = create_body(context, should)
    password = should[:password]
    body['password'] = password.respond_to?(:unwrap) ? password.unwrap : password if password
    pve_transport(context).post(context, '/access/users', body)
  end

  # 'password' is absent from attribute_map, so update_body never carries it --
  # which is required, since PUT /access/users/{userid} does not accept one.
  def update(context, name, should)
    validate_userid!(name)
    context.notice("Updating user '#{name}'")
    pve_transport(context).put(context, "/access/users/#{name}", update_body(context, should))
    enforce_password(context, name, should[:password])
  end

  def delete(context, name)
    context.notice("Deleting user '#{name}'")
    pve_transport(context).delete(context, "/access/users/#{name}")
  end

  private

  def stored_password?(userid)
    !PuppetX::ProxmoxVirtualEnvironment::SecretStore.user_password_hash(userid).nil?
  end

  # PUT /access/password is allowtoken: 0, so the REST path cannot work here
  # however the token is privileged; pveum runs locally as root@pam instead.
  #
  # Only called on real drift. pveum rewrites shadow.cfg unconditionally, so
  # calling it on every update would mint a change event on every run -- the
  # exact bug c0f5cd8 fixed, reintroduced through the side door.
  def enforce_password(context, name, password)
    return if password.nil?
    return if secret_insync?(context, name, :password, {}, password: password)

    context.notice("Setting password for user '#{name}'")
    PuppetX::ProxmoxVirtualEnvironment::Pveum.set_password(name, password)
  end

  def validate_userid!(userid)
    return if userid.match?(%r{\A[^@\s]+@[^@\s]+\z})

    raise Puppet::ResourceError, "userid must be in user@realm format, got: #{userid.inspect}"
  end
end
