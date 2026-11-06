# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveHaResource; end

# Provider for pve_ha_resource resources via the PVE REST API.
class Puppet::Provider::PveHaResource::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  # 'type' and 'digest' are deliberately absent.
  #
  # type is redundant with the sid prefix on create, and PVE rejects it as a
  # parameter on update — mapping it would send it in every PUT body.
  #
  # digest is a cluster-wide change token that PVE recomputes whenever ANY HA
  # resource changes, so mapping it would report drift on every resource every
  # time any one of them was edited.
  def self.attribute_map
    {
      'sid'          => :sid,
      'state'        => :state,
      'group'        => :group,
      'max_restart'  => :max_restart,
      'max_relocate' => :max_relocate,
      'comment'      => :comment,
      'delete'       => :delete_properties,
    }
  end

  def get(context)
    (transport_get(context, '/cluster/ha/resources') || []).map do |resource|
      pve_to_puppet(resource).merge(ensure: 'present')
    end
  end

  def create(context, name, should)
    context.notice("Creating HA resource '#{name}'")
    pve_transport(context).post(context, '/cluster/ha/resources', create_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating HA resource '#{name}'")
    pve_transport(context).put(context, "/cluster/ha/resources/#{name}", update_body(context, should))
  end

  # Removes the guest from HA management only. The guest keeps running in
  # whatever state it is currently in; it is simply no longer recovered.
  def delete(context, name)
    context.notice("Removing HA resource '#{name}'")
    pve_transport(context).delete(context, "/cluster/ha/resources/#{name}")
  end
end
