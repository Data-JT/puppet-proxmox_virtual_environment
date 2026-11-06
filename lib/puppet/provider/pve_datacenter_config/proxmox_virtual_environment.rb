# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveDatacenterConfig; end

# Provider for pve_datacenter_config resources via the PVE REST API.
#
# Maps to GET/PUT /cluster/options (datacenter.cfg). This is a singleton;
# get() always returns exactly one resource titled 'datacenter'.
#
# PUT accepts 'registered-tags' as a semicolon-separated list (per the API
# schema), but PVE >= 9.2 returns the resolved value back from GET under
# 'allowed-tags' as a JSON array instead. Both are handled here so the
# property round-trips correctly regardless of which key the server uses.
class Puppet::Provider::PveDatacenterConfig::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'description'      => :description,
      'keyboard'         => :keyboard,
      'language'         => :language,
      'console'          => :console,
      'mac_prefix'       => :mac_prefix,
      'email_from'       => :email_from,
      'http_proxy'       => :http_proxy,
      'max_workers'      => :max_workers,
      'bwlimit'          => :bwlimit,
      'migration'        => :migration,
      'next-id'          => :next_id,
      'crs'              => :crs,
      'ha'               => :ha,
      'fencing'          => :fencing,
      'tag-style'        => :tag_style,
      'user-tag-access'  => :user_tag_access,
      'u2f'              => :u2f,
      'webauthn'         => :webauthn,
      'notify'           => :notify_settings,
      'consent-text'     => :consent_text,
      'delete'           => :delete_properties,
    }
  end

  # Every attribute the type documents as "PVE property-string format". GET
  # returns some of these expanded to a Hash ('migration' does; 'bwlimit' does
  # not, on the same request), which fails the Optional[String] schema. See
  # PveBaseProvider.property_string_attributes.
  def self.property_string_attributes
    [
      :bwlimit,
      :migration,
      :next_id,
      :crs,
      :ha,
      :tag_style,
      :user_tag_access,
      :u2f,
      :webauthn,
      :notify_settings,
    ]
  end

  # GET /cluster/options returns max_workers as a String ("2"), while the type
  # declares Optional[Integer]. See PveBaseProvider.integer_attributes.
  def self.integer_attributes
    [
      :max_workers,
    ]
  end

  def get(context)
    # transport_get returns [] (not {}) when the managed transport config is
    # not yet present, since most other endpoints here return arrays. Coerce
    # that to an empty Hash so pve_to_puppet and the tag lookups below work.
    options = transport_get(context, '/cluster/options')
    options = {} unless options.is_a?(Hash)
    result = pve_to_puppet(options).merge(ensure: 'present', name: 'datacenter')
    description = result[:description]
    result[:description] = description.chomp if description.is_a?(String)
    # 'registered-tags' MUST win when present. PVE 9.2 returns both keys, and
    # they are not the same thing: 'registered-tags' is the writable property,
    # while 'allowed-tags' is a read-only derived set -- the registered tags
    # UNION every tag actually in use on a guest.
    #
    # Reading 'allowed-tags' as the current value makes the property
    # unmanageable in both directions. A tag used by some guest but not
    # registered appears in 'is' forever: declare it and Puppet sees false
    # agreement and never writes it (so it never becomes registered); leave it
    # out and Puppet sees drift on every run and rewrites the property forever.
    # Verified on pve-manager 9.2.6, where 'not-alerting' sat in allowed-tags
    # purely because one guest carried the tag.
    result[:registered_tags] = if options.key?('registered-tags')
                                 registered_tags_to_array(options['registered-tags'])
                               else
                                 Array(options['allowed-tags'])
                               end
    [result]
  end

  # 'registered-tags' is deliberately kept out of attribute_map because get/update
  # translate it specially (semicolon string <-> array, or the 'allowed-tags' JSON
  # array on PVE >= 9.2). The base delete-observability check only knows attribute_map
  # keys, so it would reject `delete_properties => ['registered-tags']`. Override
  # here to observe its deletion via the resolved :registered_tags attribute while
  # deferring all other keys (including unknown-key rejection) to the base check.
  def insync?(context, title, attribute_name, is, should)
    return super unless attribute_name == :delete_properties

    requested = Array(should[:delete_properties])
    return super unless requested.include?('registered-tags')

    others = requested - ['registered-tags']
    reject_unobservable_deletions(others)
    attribute_map = self.class.attribute_map
    tags_deleted = Array(is[:registered_tags]).empty?
    others_deleted = others.none? { |pve_key| is.key?(attribute_map[pve_key]) }
    tags_deleted && others_deleted
  end

  def create(context, name, should)
    update(context, name, should)
  end

  def update(context, _name, should)
    context.notice('Updating datacenter configuration')
    body = update_body(context, should)
    body['registered-tags'] = registered_tags_to_string(should[:registered_tags]) if should.key?(:registered_tags)
    pve_transport(context).put(context, '/cluster/options', body)
  end

  def delete(_context, name)
    raise Puppet::ResourceError, "pve_datacenter_config '#{name}' cannot be deleted"
  end

  private

  # PVE is inconsistent about the shape of this value. The API schema documents
  # 'registered-tags' as a semicolon-separated string and PUT accepts that form,
  # but GET on PVE 9.2 returns it already split into a JSON array -- the same
  # shape as 'allowed-tags'. Handle both: an Array arrives ready to use, a
  # String still needs splitting.
  def registered_tags_to_array(value)
    return [] if value.nil?
    return value if value.is_a?(Array)
    return [] if value.empty?

    value.split(';')
  end

  def registered_tags_to_string(value)
    Array(value).join(';')
  end
end
