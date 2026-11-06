# frozen_string_literal: true

require_relative '../pve_base_provider'

# @api private
module Puppet::Provider::PveBackupJob; end

# Provider for pve_backup_job resources via the PVE REST API.
class Puppet::Provider::PveBackupJob::ProxmoxVirtualEnvironment < Puppet::Provider::PveBaseProvider
  def self.attribute_map
    {
      'id'           => :id,
      'enabled'      => :enabled,
      'schedule'     => :job_schedule,
      'storage'      => :storage,
      'mode'         => :mode,
      'all'          => :all,
      'vmid'         => :vmid,
      'exclude'      => :exclude,
      'node'         => :node,
      'pool'         => :pool,
      'compress'     => :compress,
      'prune-backups' => :prune_backups,
      'mailto'        => :mailto,
      'mailnotification' => :mailnotification,
      'notification-mode' => :notification_mode,
      'notes-template' => :notes_template,
      'protected'     => :protected,
      'repeat-missed' => :repeat_missed,
      'bwlimit'      => :bwlimit,
      'fleecing'     => :fleecing,
      'performance'  => :performance,
      'comment'      => :comment,
      'delete'       => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:enabled, :all, :protected, :repeat_missed]
  end

  GUEST_ID_LIST_ATTRIBUTES = [:vmid, :exclude].freeze

  def insync?(context, name, attribute_name, is, should)
    if GUEST_ID_LIST_ATTRIBUTES.include?(attribute_name)
      should_value = should[attribute_name]
      should_value = should_value.join(',') if should_value.is_a?(Array)
      return unordered_csv_insync?(is[attribute_name], should_value)
    end

    super
  end

  def get(context)
    (transport_get(context, '/cluster/backup') || []).map do |job|
      result = pve_to_puppet(job).merge(ensure: 'present')
      # PVE decodes some property-strings (e.g. fleecing, prune-backups) into
      # nested objects in this endpoint's JSON response, unlike elsewhere in
      # the API where they remain plain strings. Re-encode them so the value
      # matches the String type declared for these attributes.
      result[:fleecing]      = property_string(result[:fleecing])      if result[:fleecing].is_a?(Hash)
      result[:prune_backups] = property_string(result[:prune_backups]) if result[:prune_backups].is_a?(Hash)
      result
    end
  end

  def create(context, name, should)
    context.notice("Creating backup job '#{name}'")
    pve_transport(context).post(context, '/cluster/backup', create_body(context, should))
  end

  def update(context, name, should)
    context.notice("Updating backup job '#{name}'")
    pve_transport(context).put(context, "/cluster/backup/#{name}", update_body(context, should))
  end

  def delete(context, name)
    context.notice("Deleting backup job '#{name}'")
    pve_transport(context).delete(context, "/cluster/backup/#{name}")
  end

  def request_body(should)
    body = super
    ['vmid', 'exclude'].each do |key|
      value = body[key]
      body[key] = value.join(',') if value.is_a?(Array)
    end
    body
  end

  private

  def property_string(hash)
    hash.map { |key, value| "#{key}=#{value}" }.sort.join(',')
  end
end
