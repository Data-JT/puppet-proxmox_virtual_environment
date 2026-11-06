# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PvePool; end

# Provider for pve_pool resources via the PVE REST API.
class Puppet::Provider::PvePool::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'poolid'  => :poolid,
      'comment' => :comment,
    }
  end

  def get(context)
    (transport_get(context, '/pools') || []).map do |pool|
      pve_to_puppet(pool).merge(ensure: 'present')
    end
  end

  def create(context, name, should)
    context.notice("Creating pool '#{name}'")
    pve_transport(context).post(context, '/pools', create_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating pool '#{name}'")
    pve_transport(context).put(context, "/pools/#{name}", update_body(context, should))
  end

  def delete(context, name)
    context.notice("Deleting pool '#{name}'")
    pve_transport(context).delete(context, "/pools/#{name}")
  end
end
