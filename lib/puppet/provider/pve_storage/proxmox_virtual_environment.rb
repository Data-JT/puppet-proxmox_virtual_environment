# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveStorage; end

# Provider for pve_storage resources via the PVE REST API.
class Puppet::Provider::PveStorage::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'storage'                => :storage,
      'type'                   => :type,
      'content'                => :content,
      'path'                   => :path,
      'server'                 => :server,
      'export'                 => :nfs_export,
      'share'                  => :share,
      'portal'                 => :portal,
      'target'                 => :target,
      'vgname'                 => :vgname,
      'thinpool'               => :thinpool,
      'pool'                   => :pool,
      'data-pool'              => :data_pool,
      'monhost'                => :monhost,
      'keyring'                => :keyring,
      'krbd'                   => :krbd,
      'datastore'              => :datastore,
      'encryption-key'         => :encryption_key,
      'username'               => :username,
      'password'               => :password,
      'nodes'                  => :nodes,
      'disable'                => :disable,
      'shared'                 => :shared,
      'prune-backups'          => :prune_backups,
      'max-protected-backups'  => :max_protected_backups,
      'namespace'              => :namespace,
      'fingerprint'            => :fingerprint,
      'skip-cert-verification' => :skip_cert_verification,
      'options'                => :options,
      'mountpoint'             => :mountpoint,
      'subdir'                 => :subdir,
      'is_mountpoint'          => :is_mountpoint,
      'create-base-path'       => :create_base_path,
      'create-subdirs'         => :create_subdirs,
      'bwlimit'                => :bwlimit,
      'blocksize'              => :blocksize,
      'preallocation'          => :preallocation,
      'sparse'                 => :sparse,
      'nocow'                  => :nocow,
      'delete'                 => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:disable, :shared, :skip_cert_verification, :krbd, :create_base_path, :create_subdirs, :sparse, :nocow]
  end

  # PVE derives 'shared' automatically for most backend types (it is forced to
  # 1 for inherently shared types such as rbd, nfs, or pbs, and forced to 0 for
  # purely local types such as lvmthin or zfspool); only these backend types
  # expose it as a settable property, and PVE rejects it as "unexpected" for
  # any other type.
  SHARED_SETTABLE_TYPES = ['btrfs', 'dir', 'esxi', 'lvm'].freeze

  # Backend types whose storage is network-accessible from every node, so PVE
  # forces shared=1 for them; all remaining non-settable types are purely
  # local and forced to shared=0.
  SHARED_FORCED_TRUE_TYPES = ['cephfs', 'cifs', 'glusterfs', 'iscsi', 'iscsidirect', 'nfs', 'pbs', 'rbd', 'zfs'].freeze

  def self.secret_attributes
    [:password]
  end

  def stored_secret(title, attribute_name)
    return nil unless attribute_name == :password

    PuppetX::ProxmoxVirtualEnvironment::SecretStore.storage_password(title)
  end

  def get(context)
    # Probed once per discovery, and non-raising: get() runs for every resource
    # in the catalog, so it must not fail merely because this agent is not on a
    # PVE node. The fail-closed check lives in insync?, which only runs for
    # attributes actually being managed.
    store_available = PuppetX::ProxmoxVirtualEnvironment::SecretStore.available?
    (transport_get(context, '/storage') || []).map do |storage|
      puppet_storage = pve_to_puppet(storage).merge(ensure: 'present')
      puppet_storage[:password] = SECRET_PLACEHOLDER if store_available && stored_password?(puppet_storage[:storage])
      puppet_storage
    end
  end

  def insync?(context, name, attribute_name, is, should)
    return unordered_csv_insync?(is[:content], should[:content]) if attribute_name == :content
    return unordered_csv_insync?(is[:nodes], should[:nodes]) if attribute_name == :nodes
    return encryption_key_insync?(is[:encryption_key], should[:encryption_key]) if attribute_name == :encryption_key

    super
  end

  def create(context, name, should)
    context.notice("Creating storage '#{name}'")
    pve_transport(context).post(context, '/storage', create_body(context, settable_should(should)))
  end

  def update(context, name, should)
    context.notice("Updating storage '#{name}'")
    immutable = init_only_attributes(context)
    body = settable_should(should).reject { |key, _| immutable.include?(key) }
    pve_transport(context).put(context, "/storage/#{name}", update_body(context, body))
  end

  def delete(context, name)
    context.notice("Deleting storage '#{name}'")
    pve_transport(context).delete(context, "/storage/#{name}")
  end

  private

  def stored_password?(storeid)
    !PuppetX::ProxmoxVirtualEnvironment::SecretStore.storage_password(storeid).nil?
  end

  # Unlike every other secret here, the encryption key needs no file read. PVE
  # writes the key's *fingerprint* into the public storage.cfg
  # (PBSPlugin.pm:530), so the API hands it straight back, and the same
  # fingerprint is a field inside the declared JSON key. That makes this a pure
  # API comparison: no root, no on-node agent, works from anywhere.
  #
  # 'autogen' generates a fresh key every time PVE receives it, so it can only
  # mean "a key must exist" -- any stricter rule would rotate the key on every
  # run. PVE stores literal 1 when the key carries no fingerprint
  # (`fingerprint || 1`), which is uncomparable, so it is accepted rather than
  # re-uploaded forever.
  def encryption_key_insync?(is, should)
    return nil if should.nil? # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

    desired = unwrap_secret(should)
    stored = is.to_s
    return !stored.empty? if desired == 'autogen'
    return true if stored == '1'

    # An absent stored value falls through to the fingerprint comparison and
    # correctly reports drift: '' never equals a real fingerprint.
    stored == encryption_key_fingerprint(desired)
  end

  def encryption_key_fingerprint(key)
    parsed = parse_encryption_key(key)
    raise Puppet::ResourceError, 'Value does not seem like a valid, JSON formatted encryption key' unless parsed.is_a?(Hash)

    parsed['fingerprint']
  end

  def parse_encryption_key(key)
    require 'json'
    JSON.parse(key)
  rescue JSON::ParserError
    nil
  end

  # PVE forces the shared flag for every backend type not in
  # SHARED_SETTABLE_TYPES. A declaration matching the forced value is accurate
  # but not settable, so it is silently omitted from the request body (and
  # stays insync because PVE reports the same value back). A declaration
  # contradicting the forced value can never converge, so it is rejected as a
  # configuration error instead of leaving a perpetual no-op diff.
  def settable_should(should)
    type = should[:type].to_s
    return should if SHARED_SETTABLE_TYPES.include?(type)

    declared = should[:shared]
    return should if declared.nil?

    forced = SHARED_FORCED_TRUE_TYPES.include?(type)
    unless to_bool(declared) == forced
      fixed = forced ? 'always shared; cannot set shared => false' : 'never shared; cannot set shared => true'
      raise Puppet::ResourceError, "storage type '#{type}' is #{fixed}"
    end

    should.reject { |key, _| key == :shared }
  end
end
