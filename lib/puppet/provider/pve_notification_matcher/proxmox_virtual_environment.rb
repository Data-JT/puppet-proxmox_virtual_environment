# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveNotificationMatcher; end

# Provider for pve_notification_matcher resources via the PVE REST API.
class Puppet::Provider::PveNotificationMatcher::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'name'           => :name,
      'target'         => :target,
      'match-severity' => :match_severity,
      'match-calendar' => :match_calendar,
      'match-field'    => :match_field,
      'mode'           => :mode,
      'invert-match'   => :invert_match,
      'disable'        => :disable,
      'comment'        => :comment,
      'delete'         => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:invert_match, :disable]
  end

  def get(context)
    (transport_get(context, '/cluster/notifications/matchers') || []).map do |matcher|
      pve_to_puppet(matcher).merge(ensure: 'present')
    end
  end

  def self.delete_properties_as_array?
    true
  end

  def create(context, name, should)
    context.notice("Creating notification matcher '#{name}'")
    pve_transport(context).post(context, '/cluster/notifications/matchers', create_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating notification matcher '#{name}'")
    pve_transport(context).put(context, "/cluster/notifications/matchers/#{name}", update_body(context, should))
  end

  def delete(context, name)
    context.notice("Deleting notification matcher '#{name}'")
    pve_transport(context).delete(context, "/cluster/notifications/matchers/#{name}")
  end
end
