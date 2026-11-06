# frozen_string_literal: true

require_relative '../pve_sdn_base_provider'

# @api private
module Puppet::Provider::PveSdnApply; end

# Provider for pve_sdn_apply resources via the PVE REST API.
#
# This is the only provider in the module that calls PUT /cluster/sdn, the
# operation that regenerates /etc/network/interfaces.d/sdn on every node and
# reloads networking there. Everything else writes pending configuration.
class Puppet::Provider::PveSdnApply::ProxmoxVirtualEnvironment < Puppet::Provider::PveSdnBaseProvider
  APPLY_PATH = '/cluster/sdn'
  VNETS_PATH = '/cluster/sdn/vnets'
  TASK_STATUS_PATH = '/nodes/{node}/tasks/{upid}/status'
  POLL_INTERVAL = 2
  DEFAULT_TIMEOUT = 300

  # Object classes that participate in the pending/running split, with the PVE
  # response key holding each one's identifier. ipams and dns are absent on
  # purpose: they have no running-config section and take effect immediately.
  PENDING_SOURCES = {
    'zones'       => 'zone',
    'vnets'       => 'vnet',
    'controllers' => 'controller',
  }.freeze

  def self.attribute_map
    { 'name' => :name }
  end

  def get(context)
    pending = collect_pending(context)
    [{
      name:            'sdn',
      ensure:          'present',
      applied:         pending.empty?,
      pending_objects: pending,
    }]
  end

  # Never reached: get always reports the singleton as present, and the type
  # constrains ensure to present, so SimpleProvider only ever routes to update.
  def create(_context, _name, _should)
    raise Puppet::ResourceError, 'pve_sdn_apply cannot be created; it represents an action on the existing SDN configuration'
  end

  def delete(_context, _name)
    raise Puppet::ResourceError, 'pve_sdn_apply cannot be removed; it represents an action on the existing SDN configuration'
  end

  def update(context, _name, should)
    assert_applied_true(should[:applied])
    context.warning('Applying SDN configuration: this reloads networking on every cluster node')
    upid = sdn_call(context, 'PUT', APPLY_PATH)
    return unless should.fetch(:wait, true)

    wait_for_task(context, upid, should[:timeout] || DEFAULT_TIMEOUT)
  end

  private

  def collect_pending(context)
    pending = PENDING_SOURCES.flat_map do |kind, id_key|
      pending_entries(transport_get(context, "#{APPLY_PATH}/#{kind}", 'pending' => 1), kind, id_key)
    end
    pending + pending_subnets(context)
  end

  def pending_subnets(context)
    vnet_names(context).flat_map do |vnet|
      pending_entries(transport_get(context, "#{VNETS_PATH}/#{vnet}/subnets", 'pending' => 1), 'subnets', 'subnet')
    end
  end

  def vnet_names(context)
    Array(transport_get(context, VNETS_PATH)).filter_map { |entry| entry['vnet'] }
  end

  def assert_applied_true(applied)
    return if applied

    raise Puppet::ResourceError, "pve_sdn_apply only supports applied => true; got #{applied.inspect}"
  end

  def pending_entries(entries, kind, id_key)
    Array(entries).filter_map do |entry|
      state = entry['state']
      "#{kind}/#{entry[id_key]}: #{state}" if PENDING_STATES.include?(state)
    end
  end

  # PVE runs the apply in a background worker and returns its task ID. Not
  # waiting would report a successful change for an apply that failed halfway
  # through regenerating the cluster's network configuration.
  def wait_for_task(context, upid, timeout)
    node = task_node(upid)
    deadline = monotonic_now + timeout
    loop do
      status = task_status(context, node, upid)
      return report_task(context, status, upid) if status['status'] == 'stopped'

      assert_before_deadline(deadline, timeout, upid)
      sleep(POLL_INTERVAL)
    end
  end

  def task_node(upid)
    node = upid.to_s.split(':')[1].to_s
    raise Puppet::ResourceError, "PVE returned an unusable task ID for the SDN apply: #{upid.inspect}" if node.empty?

    node
  end

  def assert_before_deadline(deadline, timeout, upid)
    return if monotonic_now < deadline

    raise Puppet::ResourceError, "Timed out after #{timeout}s waiting for SDN apply task #{upid}"
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def task_status(context, node, upid)
    status = pve_transport(context).call(context, 'GET', TASK_STATUS_PATH, path_params: { node: node, upid: upid })
    status.is_a?(Hash) ? status : {}
  end

  def report_task(context, status, upid)
    exitstatus = status['exitstatus'].to_s
    raise Puppet::ResourceError, "SDN apply task #{upid} failed: #{exitstatus}" unless exitstatus == 'OK'

    context.notice('SDN configuration applied on all cluster nodes')
  end
end
