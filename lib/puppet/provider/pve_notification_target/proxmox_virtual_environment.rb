# frozen_string_literal: true

require 'base64'
require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveNotificationTarget; end

# Provider for pve_notification_target resources via the PVE REST API.
class Puppet::Provider::PveNotificationTarget::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  TARGET_TYPES = ['sendmail', 'smtp', 'gotify', 'webhook'].freeze unless const_defined?(:TARGET_TYPES)

  def self.attribute_map
    {
      'name'          => :name,
      'comment'       => :comment,
      'disable'       => :disable,
      'author'        => :author,
      'from-address'  => :from_address,
      'mailto'        => :mailto,
      'mailto-user'   => :mailto_user,
      'server'        => :server,
      'port'          => :port,
      'mode'          => :mode,
      'username'      => :username,
      'password'      => :smtp_password,
      'token'         => :token,
      'url'           => :url,
      'method'        => :http_method,
      'body'          => :body,
      'header'        => :header,
      'secret'        => :secret,
      'delete'        => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:disable]
  end

  def self.delete_properties_as_array?
    true
  end

  # PVE names the stored field differently per endpoint type, and the private
  # config is sectioned by that type, so the lookup needs both.
  SECRET_FIELDS = {
    smtp_password: 'password',
    token:         'token',
    secret:        'secret',
  }.freeze

  def self.secret_attributes
    SECRET_FIELDS.keys
  end

  # The endpoint type is not derivable from the title, so capture it before
  # delegating. Falls back to the declared type for a resource that discovery
  # did not return.
  def secret_insync?(context, title, attribute_name, is, should)
    @secret_type = (is[:type] || should[:type]).to_s
    super
  end

  def stored_secret(title, attribute_name)
    field = SECRET_FIELDS[attribute_name]
    return nil if field.nil?

    PuppetX::ProxmoxVirtualEnvironment::SecretStore.notification_secret(@secret_type, title, field)
  end

  # Webhook secrets are an unordered name/value set, not a list: PVE does not
  # preserve declaration order, so comparing them as arrays would re-PUT an
  # identical value on every run. smtp_password and token stay plain strings
  # and fall through to the base implementation.
  def secret_matches?(stored, desired)
    return super unless desired.is_a?(Array)

    stored_secret_map(stored) == desired_secret_map(desired)
  end

  def get(context)
    @type_by_name = {}
    results = []
    TARGET_TYPES.each do |target_type|
      items = transport_get(context, "/cluster/notifications/endpoints/#{target_type}") || []
      items.each do |item|
        puppet_hash = pve_to_puppet(item).merge(ensure: 'present', type: target_type)
        decode_webhook_fields!(puppet_hash) if target_type == 'webhook'
        @type_by_name[item['name']] = target_type
        results << puppet_hash
      end
    end
    results
  end

  def create(context, name, should)
    target_type = should[:type]
    context.notice("Creating #{target_type} notification target '#{name}'")
    body = create_body(context, should)
    encode_webhook_fields!(body) if target_type == 'webhook'
    pve_transport(context).post(context, "/cluster/notifications/endpoints/#{target_type}", body)
  end

  def update(context, name, should)
    target_type = should[:type]
    context.notice("Updating #{target_type} notification target '#{name}'")
    body = update_body(context, should)
    encode_webhook_fields!(body) if target_type == 'webhook'
    pve_transport(context).put(context, "/cluster/notifications/endpoints/#{target_type}/#{name}", body)
  end

  def delete(context, name)
    target_type = (@type_by_name || {})[name]
    if target_type.nil?
      raise Puppet::ResourceError,
            "unknown notification target type for '#{name}' (was it discovered?)"
    end
    context.notice("Deleting notification target '#{name}'")
    pve_transport(context).delete(context, "/cluster/notifications/endpoints/#{target_type}/#{name}")
  end

  private

  def encode_webhook_fields!(body)
    body['body'] = Base64.strict_encode64(body['body']) if body.key?('body')
    body['header'] = encode_property_strings(body['header']) if body.key?('header')
    body['secret'] = encode_property_strings(body['secret']) if body.key?('secret')
  end

  def decode_webhook_fields!(attributes)
    attributes[:body] = Base64.strict_decode64(attributes[:body]) if attributes.key?(:body)
    attributes[:header] = decode_property_strings(attributes[:header]) if attributes.key?(:header)
    attributes[:secret] = decode_property_strings(attributes[:secret]) if attributes.key?(:secret)
  rescue ArgumentError
    # Preserve malformed API values so Puppet reports drift instead of hiding it.
  end

  def encode_property_strings(items)
    Array(items).map do |item|
      next item unless item.is_a?(Hash)

      name = item['name'] || item[:name]
      value = item['value'] || item[:value]
      result = "name=#{name}"
      result += ",value=#{Base64.strict_encode64(value.to_s)}" unless value.nil?
      result
    end
  end

  # notifications.cfg holds one "name=<n>,value=<base64>" line per secret,
  # which is the same property-string form the API uses, so the existing
  # decoder handles it.
  def stored_secret_map(stored)
    decode_property_strings(stored.to_s.lines.map(&:strip)).to_h do |entry|
      [entry['name'].to_s, entry['value'].to_s]
    end
  end

  def desired_secret_map(desired)
    desired.to_h do |entry|
      name = entry['name'] || entry[:name]
      value = entry['value'] || entry[:value]
      [name.to_s, unwrap_secret(value).to_s]
    end
  end

  def decode_property_strings(items)
    Array(items).map do |item|
      values = item.split(',').to_h { |part| part.split('=', 2) }
      result = { 'name' => values['name'] }
      result['value'] = Base64.strict_decode64(values['value']) if values.key?('value')
      result
    end
  end
end
