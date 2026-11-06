# frozen_string_literal: true

require 'puppet/resource_api/simple_provider'
require_relative '../../puppet_x/proxmox_virtual_environment/config' # see config.rb: bare require breaks in puppetserver
require_relative '../../puppet_x/proxmox_virtual_environment/secret_store' # ditto
require 'yaml'

# Base provider with shared PVE attribute mapping helpers.
class Puppet::Provider::PveBaseProvider < Puppet::ResourceApi::SimpleProvider
  # Raised by build_transport when the managed transport config file is absent.
  # Discovery (transport_get) rescues this specifically to treat a not-yet-applied
  # transport as an empty result, without swallowing unrelated ResourceErrors.
  class TransportConfigMissingError < Puppet::ResourceError; end

  def self.attribute_map
    {}
  end

  def self.boolean_attributes
    []
  end

  # Attributes whose PVE value is a "property string" (k=v,k=v,...).
  #
  # PVE is inconsistent about how it returns these. On GET /cluster/options,
  # 'bwlimit' comes back as a plain String ("migration=500000") while
  # 'migration' comes back as an expanded Hash
  # ({"type" => "secure", "network" => "192.0.2.0/24"}) -- even though the
  # PUT side accepts the string form for both and the type schema declares
  # Optional[String]. An unconverted Hash fails schema validation with:
  #
  #   Provider returned data that does not match the Type Schema
  #
  # which makes the resource unmanageable on every subsequent run, while the
  # value on disk is perfectly correct.
  #
  # Providers list such attributes here to get both normalisation on read
  # (Hash -> property string) and order-insensitive comparison, since PVE
  # reorders the keys and a raw string compare would otherwise re-PUT the
  # identical value on every run.
  def self.property_string_attributes
    []
  end

  # Attributes the type declares as Integer but PVE returns as a String.
  #
  # Same failure as property_string_attributes, one type over: GET
  # /cluster/options returns 'max_workers' as "2", not 2, so an
  # Optional[Integer] attribute fails schema validation with
  #
  #   Provider returned data that does not match the Type Schema
  #     * max_workers: 2 (expects a value of type Undef or Integer, got String)
  #
  # on every run after the value is first set -- the PUT succeeds and the value
  # on disk is correct, but the resource is then unmanageable.
  #
  # Declaring the type as Variant[Integer, String] would silence it and be
  # wrong: 'is' would be "2" while 'should' is 2, so the resource would never
  # be insync and would re-PUT the identical value forever. Coerce on read
  # instead and keep the type honest.
  def self.integer_attributes
    []
  end

  # Read-side coercion for integer_attributes. Anything that is not cleanly an
  # integer is returned untouched, so a genuinely unexpected value still
  # surfaces as a schema error rather than being silently coerced to 0 by
  # String#to_i.
  def self.to_integer(value)
    return value if value.is_a?(Integer)
    return value unless value.is_a?(String) && value.match?(%r{\A-?\d+\z})

    value.to_i
  end

  # Stable 'is' value reported for a managed secret. Must not vary between
  # runs -- a changing placeholder would itself read as drift.
  SECRET_PLACEHOLDER = '[secret managed]'

  # Attributes whose real value lives in /etc/pve/priv rather than in the API
  # response, because PVE never returns them. Providers listing an attribute
  # here must implement stored_secret.
  #
  # Not every secret belongs here: pve_storage's encryption_key is compared
  # against the fingerprint PVE returns from the API, and pve_realm's
  # client_key round-trips verbatim, so neither needs the store.
  def self.secret_attributes
    []
  end

  def self.config_path
    File.join(Puppet.settings[:confdir], PuppetX::ProxmoxVirtualEnvironment::CONFIG_FILENAME)
  end

  def self.build_transport(context)
    require 'puppet/transport/proxmox_virtual_environment'
    config = load_transport_config
    Puppet::Transport::ProxmoxVirtualEnvironment.new(context, config)
  rescue Errno::ENOENT
    raise TransportConfigMissingError,
          "PVE transport config not found at #{config_path}; " \
          'ensure the proxmox_virtual_environment class is applied before managing PVE resources'
  end

  def self.load_transport_config
    config = YAML.safe_load_file(config_path)
    unless config.is_a?(Hash)
      raise Puppet::ResourceError,
            "PVE transport config at #{config_path} is empty or invalid"
    end
    config.transform_keys(&:to_sym)
  end

  def pve_transport(context)
    signature = transport_config_signature
    if @pve_transport.nil? || signature != @transport_config_signature
      @pve_transport = self.class.build_transport(context)
      @transport_config_signature = signature
    end
    @pve_transport
  end

  # State discovery happens before catalog resources are applied. Treat a
  # missing managed transport file as an empty result; set() refreshes state
  # after the transport class has been applied.
  def transport_get(context, path, query = nil)
    transport = pve_transport(context)
    return transport.get(context, path) if query.nil?

    transport.get(context, path, query)
  rescue TransportConfigMissingError
    @transport_config_missing = true
    []
  end

  def set(context, changes)
    assert_cluster_manager!
    changes = refresh_changes(context, changes) if @transport_config_missing
    validate_init_only_changes!(context, changes)
    super
  end

  # Returning nil is the Resource API insync? contract: it signals "I don't handle
  # this property, fall back to the default comparison" -- not a boolean predicate,
  # so nil must not be collapsed to false.
  def insync?(context, title, attribute_name, is, should)
    return delete_properties_insync?(is, should) if attribute_name == :delete_properties

    provider = self.class
    if provider.secret_attributes.include?(attribute_name)
      return secret_insync?(context, title, attribute_name, is, should)
    end
    return nil unless provider.property_string_attributes.include?(attribute_name) # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

    property_string_insync?(is[attribute_name], should[attribute_name])
  end

  # A secret is in sync when the copy PVE persists on the node matches the
  # declared one.
  #
  # Fails closed: if the store cannot be read we raise rather than assume a
  # match. A false "in sync" here would silently disable enforcement, which is
  # the failure mode this whole mechanism exists to remove.
  #
  # An undeclared secret is always in sync -- Puppet is not managing it, so
  # whatever PVE holds is by definition correct.
  def secret_insync?(_context, title, attribute_name, _is, should)
    desired = unwrap_secret(should[attribute_name])
    return true if desired.nil?

    PuppetX::ProxmoxVirtualEnvironment::SecretStore.assert_available!(attribute_name)
    stored = stored_secret(title, attribute_name)
    return false if stored.nil?

    secret_matches?(stored, desired)
  end

  def stored_secret(_title, _attribute_name)
    raise NotImplementedError,
          "#{self.class} declares secret_attributes but does not implement stored_secret"
  end

  # Plaintext against plaintext by default, which covers five of the six
  # secrets. pve_user overrides this to verify a plaintext against a crypt(3)
  # hash, and pve_notification_target to compare the webhook secret set.
  def secret_matches?(stored, desired)
    stored == desired
  end

  # Hiera/eyaml lookups yield a plain String; a Sensitive() declaration and the
  # Resource API's own re-wrapping both yield something with #unwrap.
  def unwrap_secret(value)
    return nil if value.nil?

    value.respond_to?(:unwrap) ? value.unwrap : value
  end

  # PVE returns some comma-separated lists (e.g. storage 'content') reordered
  # into its own canonical order, regardless of the order they were declared
  # or sent in. Treat such attributes as unordered sets so runs converge
  # instead of re-sending the declared order on every run.
  def unordered_csv_insync?(is, should)
    is.to_s.split(',').sort == should.to_s.split(',').sort
  end

  # Property strings are an unordered set of key=value pairs, so compare them
  # parsed rather than as raw text. PVE renders them back in its own key order
  # (and may return them expanded to a Hash), so a string comparison would
  # report a change on every run and re-PUT an identical value forever.
  def property_string_insync?(is, should)
    parse_property_string(is) == parse_property_string(should)
  end

  # Hash -> "key=value,key=value". Keys are sorted so the value Puppet reports
  # is stable between runs; comparison is order-insensitive regardless.
  def serialize_property_string(value)
    return value unless value.is_a?(Hash)

    value.sort_by { |key, _val| key.to_s }.map { |key, val| "#{key}=#{val}" }.join(',')
  end

  # Bare tokens (PVE's optional "default key" form, e.g. 'secure,network=...'
  # for 'type=secure,network=...') are keyed by position, so they compare equal
  # to themselves but not to the explicit form. Declare the explicit form -- it
  # is what the API returns and what the type documentation shows.
  #
  # An unset value needs no special case: nil.to_s splits to an empty list, so
  # it parses to the empty Hash an absent property string should compare as.
  def parse_property_string(value)
    return value.to_h { |key, val| [key.to_s, val.to_s] } if value.is_a?(Hash)

    value.to_s.split(',').each_with_index.to_h do |token, index|
      token.include?('=') ? token.split('=', 2).map(&:strip) : [index.to_s, token.strip]
    end
  end

  def pve_to_puppet(hash)
    result = {}
    boolean_attributes = self.class.boolean_attributes
    property_string_attributes = self.class.property_string_attributes
    integer_attributes = self.class.integer_attributes
    self.class.attribute_map.each do |pve_key, puppet_key|
      pve_key = pve_key.to_s
      next unless hash.key?(pve_key)
      value = hash[pve_key]
      value = to_bool(value) if boolean_attributes.include?(puppet_key)
      value = serialize_property_string(value) if property_string_attributes.include?(puppet_key)
      value = self.class.to_integer(value) if integer_attributes.include?(puppet_key)
      result[puppet_key] = value
    end
    result
  end

  def puppet_to_pve(hash)
    result = {}
    boolean_attributes = self.class.boolean_attributes
    self.class.attribute_map.each do |pve_key, puppet_key|
      next unless hash.key?(puppet_key)
      value = hash[puppet_key]
      next if value.nil?
      value = value.unwrap if value.respond_to?(:unwrap)
      value = to_bool(value) if boolean_attributes.include?(puppet_key)
      result[pve_key.to_s] = value
    end
    result
  end

  def request_body(should)
    body = should.dup
    body.delete(:ensure)
    normalize_delete_properties(puppet_to_pve(body))
  end

  def update_body(context, should)
    body = should.reject { |attribute, _value| context.type.namevars.include?(attribute) }
    request_body(body)
  end

  # Body for create requests. Never carries 'delete': a resource being created
  # has no properties to delete, and the API rejects the parameter on POST.
  def create_body(_context, should)
    request_body(should).except('delete')
  end

  # Clearing optional properties: `delete_properties` names API properties to
  # remove on update. A provider opts in by mapping 'delete' => :delete_properties
  # in attribute_map, which passes the list to the endpoint's `delete` parameter.
  #
  # Whether that parameter is sent as a JSON list rather than a comma-separated
  # string. PVE's Perl API takes the string on most endpoints; the Rust APIs of
  # PBS and PDM take the list.
  def self.delete_properties_as_array?
    false
  end

  # GET never reports delete_properties, so it is in sync once none of the
  # named properties is present any more: the delete is sent only while one
  # still is. A name outside attribute_map could never be observed as gone and
  # would re-send the delete on every run, so it is rejected instead.
  def delete_properties_insync?(current, desired)
    requested = Array(desired[:delete_properties])
    reject_unobservable_deletions(requested)
    attribute_map = self.class.attribute_map
    requested.none? { |api_key| current.key?(attribute_map[api_key]) }
  end

  private

  def assert_cluster_manager!
    manager = self.class.load_transport_config[:cluster_manager].to_s
    certname = Puppet[:certname].to_s

    if manager.empty?
      raise Puppet::ResourceError,
            "PVE transport config at #{self.class.config_path} has no cluster_manager; refusing PVE API changes"
    end
    return if certname == manager

    raise Puppet::ResourceError,
          "PVE API changes are restricted to cluster manager #{manager}; current Puppet certname is #{certname}"
  rescue Errno::ENOENT
    raise Puppet::ResourceError,
          "PVE transport config not found at #{self.class.config_path}; refusing PVE API changes"
  end

  def transport_config_signature
    stat = File.stat(self.class.config_path)
    [stat.mtime.to_f, stat.size]
  rescue Errno::ENOENT
    nil
  end

  def refresh_changes(context, changes)
    @pve_transport = nil
    @transport_config_signature = nil
    @transport_config_missing = false
    current = get(context) || []

    changes.transform_values do |change|
      should = change[:should]
      actual = current.find do |resource|
        context.type.namevars.all? { |namevar| resource[namevar] == should[namevar] }
      end
      change.merge(is: actual || absent_state(context, should))
    end
  end

  def init_only_attributes(context)
    context.type.attributes.select { |_name, options| options[:behaviour] == :init_only }.keys
  end

  def validate_init_only_changes!(context, changes)
    init_only = init_only_attributes(context)
    changes.each_value do |change|
      is = change[:is] || {}
      should = change[:should] || {}
      next unless is[:ensure].to_s == 'present' && should[:ensure].to_s == 'present'

      changed = init_only.select { |attribute| should.key?(attribute) && is[attribute] != should[attribute] }
      next if changed.empty?

      raise Puppet::ResourceError, "Cannot change immutable PVE attributes: #{changed.join(', ')}"
    end
  end

  def absent_state(context, should)
    context.type.namevars.to_h { |namevar| [namevar, should[namevar]] }.merge(ensure: 'absent')
  end

  def normalize_delete_properties(body)
    return body unless body.key?('delete')

    values = Array(body['delete'])
    body['delete'] = self.class.delete_properties_as_array? ? values : values.join(',')
    body
  end

  def reject_unobservable_deletions(requested)
    unknown = requested.reject { |api_key| self.class.attribute_map.key?(api_key) }
    return if unknown.empty?

    raise Puppet::ResourceError, "Cannot observe deleted PVE properties: #{unknown.join(', ')}"
  end

  def to_bool(value)
    return true if [true, 1, '1', 'true', :true].include?(value)
    return false if [false, 0, '0', 'false', :false].include?(value)

    value
  end
end
