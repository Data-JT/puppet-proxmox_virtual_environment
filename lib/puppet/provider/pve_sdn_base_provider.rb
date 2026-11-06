# frozen_string_literal: true

require_relative 'pve_base_provider'

# Shared behaviour for the SDN providers.
#
# Everything in this class writes *pending* configuration only. PVE splits SDN
# into two phases: a create/update/delete lands in /etc/pve/sdn/<kind>.cfg and
# changes nothing on the wire, and a separate `PUT /cluster/sdn` regenerates
# /etc/network/interfaces.d/sdn on every node and reloads networking. Only
# pve_sdn_apply performs that second phase, and only when a user has
# deliberately declared it.
class Puppet::Provider::PveSdnBaseProvider < Puppet::Provider::PveBaseProvider
  # PVE guards every SDN mutation with lock_sdn_config (pve-network,
  # PVE/Network/SDN.pm). If /etc/pve/sdn/.lock-token exists and the caller does
  # not present the matching token, the write dies with this message. This
  # module never acquires the lock -- a cluster-wide lock left behind by a
  # crashed agent would block the web UI indefinitely -- so the only correct
  # response is to report it in terms an operator can act on.
  LOCKED_PATTERN = %r{invalid lock token provided}i

  LOCKED_MESSAGE =
    'SDN configuration is locked by another client. Release it in the PVE web UI, ' \
    'or on a cluster node run: pvesh delete /cluster/sdn/lock --force'

  # PVE object states reported by a `?pending=1` read.
  PENDING_STATES = ['new', 'changed', 'deleted'].freeze

  class << self
    # Collection endpoint, e.g. '/cluster/sdn/zones'.
    def sdn_collection_path
      raise NotImplementedError, "#{self} must define sdn_collection_path"
    end

    # PVE response key holding the object identifier, e.g. 'zone'.
    def sdn_id_key
      raise NotImplementedError, "#{self} must define sdn_id_key"
    end

    # Noun used in change notices.
    def sdn_object_label
      sdn_id_key
    end

    # Whether this object class participates in the pending/apply mechanism.
    # ipams and dns do not: their index endpoints accept neither `pending` nor
    # `running`, they have no section in .running-config, and PVE consults them
    # live. Changes to them take effect immediately.
    def pending_aware?
      true
    end

    # Attributes PVE stores as a comma-separated list and hands back in its own
    # order. Compared as unordered sets so a reordered declaration does not
    # re-PUT an identical value on every run.
    def unordered_csv_attributes
      []
    end

    # Attributes PVE accepts as an Array of property strings but returns as an
    # Array of expanded Hashes (see PVE/API2/Network/SDN/Subnets.pm, which runs
    # get_dhcp_ranges on every read). Both the element encoding and the element
    # order have to be normalised before comparison.
    def property_string_array_attributes
      []
    end

    # Attributes declared `type => 'array'` in the PVE schema but persisted in
    # the section config as a comma-separated list, so a read may hand back
    # either shape. Normalised to a sorted Array[String] on both sides: an
    # unconverted String would fail the type schema with "Provider returned
    # data that does not match the Type Schema", and an unsorted one would
    # report a change on every run.
    def string_list_attributes
      []
    end
  end

  def get(context)
    states = pending_states(context)
    sdn_entries(context).map { |entry| to_puppet_entry(entry, states) }
  end

  def create(context, name, should)
    provider = self.class
    context.notice("Creating SDN #{provider.sdn_object_label} '#{name}' (pending; not applied)")
    sdn_call(context, 'POST', provider.sdn_collection_path, body: create_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating SDN #{self.class.sdn_object_label} '#{name}' (pending; not applied)")
    sdn_call(context, 'PUT', object_path,
             body: update_body(context, mutable_should(context, should)),
             path_params: path_params(name))
  end

  def delete(context, name)
    context.notice("Deleting SDN #{self.class.sdn_object_label} '#{name}' (pending; not applied)")
    sdn_call(context, 'DELETE', object_path, path_params: path_params(name))
  end

  def insync?(context, title, attribute_name, is, should)
    provider = self.class
    current = is[attribute_name]
    desired = should[attribute_name]

    return property_string_array_insync?(current, desired) if provider.property_string_array_attributes.include?(attribute_name)
    return unordered_csv_insync?(current, desired) if provider.unordered_csv_attributes.include?(attribute_name)
    return normalize_string_list(current) == normalize_string_list(desired) if provider.string_list_attributes.include?(attribute_name)

    super
  end

  # Arrays of property strings are an unordered collection of unordered
  # key/value sets, so both levels are canonicalised before comparing.
  def property_string_array_insync?(is, should)
    normalize_property_string_array(is) == normalize_property_string_array(should)
  end

  def normalize_property_string_array(value)
    Array(value).map { |item| serialize_property_string(parse_property_string(item)) }.sort
  end

  # Accepts either shape PVE may hand back for an array-typed attribute.
  def normalize_string_list(value)
    items = value.is_a?(Array) ? value : value.to_s.split(',')
    items.map { |item| item.to_s.strip }.reject(&:empty?).sort
  end

  def pve_to_puppet(hash)
    provider = self.class
    normalize_lists(super, provider.property_string_array_attributes, provider.string_list_attributes)
  end

  def puppet_to_pve(hash)
    provider = self.class
    normalize_lists(super,
                    pve_keys_for(provider.property_string_array_attributes),
                    pve_keys_for(provider.string_list_attributes))
  end

  # Drops the attributes PVE refuses to change after creation. Shared with the
  # subnet provider, which addresses a nested path and so cannot use the
  # generic update above.
  def mutable_should(context, should)
    immutable = init_only_attributes(context)
    should.reject { |key, _value| immutable.include?(key) }
  end

  private

  # Raw PVE entries for this object class. Reads the plain endpoint, not
  # `?pending=1`: a pending read returns the *running* values at the top level
  # and buries the configured ones in a `pending` sub-hash (pending_config,
  # PVE/Network/SDN.pm), so comparing against it would report a change, PUT the
  # identical value and never converge.
  def sdn_entries(context)
    transport_get(context, self.class.sdn_collection_path) || []
  end

  def to_puppet_entry(entry, states)
    hash = pve_to_puppet(entry).merge(ensure: 'present')
    state = states[entry[self.class.sdn_id_key]]
    hash[:pending_state] = state if state
    hash
  end

  # Second read, purely to surface whether an object is applied. Only the
  # `state` key is taken; the values alongside it are the running ones and must
  # not reach the property comparison.
  def pending_states(context)
    provider = self.class
    return {} unless provider.pending_aware?

    collect_pending_states(transport_get(context, provider.sdn_collection_path, 'pending' => 1))
  end

  def collect_pending_states(entries)
    id_key = self.class.sdn_id_key
    Array(entries).each_with_object({}) do |entry, states|
      state = entry['state']
      states[entry[id_key]] = state if PENDING_STATES.include?(state)
    end
  end

  # Path template for a single object; expanded with path_params.
  def object_path
    provider = self.class
    "#{provider.sdn_collection_path}/{#{provider.sdn_id_key}}"
  end

  def path_params(name)
    { self.class.sdn_id_key => name }
  end

  def sdn_call(context, method, path, body: nil, path_params: {})
    pve_transport(context).call(context, method, path, body: body, path_params: path_params)
  rescue Puppet::ResourceError => error
    message = error.message
    raise unless LOCKED_PATTERN.match?(message)

    raise Puppet::ResourceError, "#{LOCKED_MESSAGE} (PVE said: #{message})"
  end

  # Single pass over the attribute hash: rewriting the two list-shaped families
  # in place would read each key twice and mutate the argument.
  def normalize_lists(result, property_string_keys, string_list_keys)
    result.each_with_object({}) do |(key, value), normalized|
      normalized[key] =
        if property_string_keys.include?(key)
          normalize_property_string_array(value)
        elsif string_list_keys.include?(key)
          normalize_string_list(value)
        else
          value
        end
    end
  end

  def pve_keys_for(attributes)
    attribute_map = self.class.attribute_map
    attributes.filter_map { |attribute| attribute_map.key(attribute)&.to_s }
  end
end
