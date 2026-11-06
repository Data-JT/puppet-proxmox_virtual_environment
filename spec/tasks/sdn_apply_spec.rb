# frozen_string_literal: true

require 'spec_helper'
require 'cgi'
require 'stringio'
require_relative '../../tasks/sdn_apply'

RSpec.describe 'sdn_apply task' do
  let(:upid) { 'UPID:node1:0000ABCD:00112233:66AA0000:reloadnetworkall::root@pam:' }
  let(:status_url) { "https://pve.example.com:8006/api2/json/nodes/node1/tasks/#{CGI.escape(upid).gsub('+', '%20')}/status" }

  def run_and_capture(input)
    original = $stdout
    $stdout = StringIO.new
    exit_status = 0
    begin
      PveSdnApplyTask.run_task(input)
    rescue SystemExit => e
      exit_status = e.status
    ensure
      output = $stdout.string
      $stdout = original
    end
    [output, exit_status]
  end

  def base_input(overrides = {})
    {
      'host' => 'pve.example.com',
      'token_id' => 'puppet@pve!puppet',
      'token_secret' => 'secret',
      'ssl_verify' => false,
    }.merge(overrides)
  end

  before(:each) do
    allow(PveSdnApplyTask).to receive(:sleep)
  end

  it 'applies and waits for the worker task by default' do
    stub_request(:put, 'https://pve.example.com:8006/api2/json/cluster/sdn')
      .with(headers: { 'Authorization' => 'PVEAPIToken=puppet@pve!puppet=secret' })
      .to_return(status: 200, body: { data: upid }.to_json)
    stub_request(:get, status_url)
      .to_return(status: 200, body: { data: { status: 'stopped', exitstatus: 'OK' } }.to_json)

    output, exit_status = run_and_capture(base_input)

    expect(exit_status).to eq(0)
    expect(JSON.parse(output)).to include('success' => true, 'upid' => upid, 'waited' => true, 'exitstatus' => 'OK')
  end

  it 'fails when the apply worker exits with an error' do
    stub_request(:put, 'https://pve.example.com:8006/api2/json/cluster/sdn')
      .to_return(status: 200, body: { data: upid }.to_json)
    stub_request(:get, status_url)
      .to_return(status: 200, body: { data: { status: 'stopped', exitstatus: 'command failed' } }.to_json)

    output, exit_status = run_and_capture(base_input)

    expect(exit_status).to eq(1)
    expect(JSON.parse(output)['_error']).to include('kind' => 'proxmox_virtual_environment/sdn-apply-error')
    expect(JSON.parse(output)['_error']['msg']).to match(%r{failed})
  end

  it 'returns the task ID without polling when wait is false' do
    stub_request(:put, 'https://pve.example.com:8006/api2/json/cluster/sdn')
      .to_return(status: 200, body: { data: upid }.to_json)

    output, exit_status = run_and_capture(base_input('wait' => false))

    expect(exit_status).to eq(0)
    expect(JSON.parse(output)).to include('waited' => false, 'upid' => upid)
  end

  # The whole point of the dry run: it must never mutate anything.
  it 'previews the change without applying it' do
    stub_request(:get, 'https://pve.example.com:8006/api2/json/cluster/sdn/dry-run?node=node1')
      .to_return(status: 200, body: { data: { 'interfaces-diff' => '+auto vxlan_vnet1', 'frr-diff' => '' } }.to_json)
    apply = stub_request(:put, 'https://pve.example.com:8006/api2/json/cluster/sdn')

    output, exit_status = run_and_capture(base_input('dry_run' => true, 'node' => 'node1'))

    expect(exit_status).to eq(0)
    expect(JSON.parse(output)).to include('dry_run' => true, 'node' => 'node1')
    expect(JSON.parse(output)['diff']).to include('interfaces-diff' => '+auto vxlan_vnet1')
    expect(apply).not_to have_been_requested
  end

  it 'refuses a dry run without a node' do
    output, exit_status = run_and_capture(base_input('dry_run' => true))

    expect(exit_status).to eq(1)
    expect(JSON.parse(output)['_error']['msg']).to match(%r{dry_run requires a node})
  end

  it 'surfaces an API failure as a structured Bolt error' do
    stub_request(:put, 'https://pve.example.com:8006/api2/json/cluster/sdn')
      .to_return(status: 500, body: { errors: { sdn: 'invalid lock token provided!' } }.to_json)

    output, exit_status = run_and_capture(base_input)

    expect(exit_status).to eq(1)
    error = JSON.parse(output)['_error']
    expect(error['msg']).to match(%r{HTTP 500})
    expect(error['details']['status']).to eq(500)
  end

  it 'rejects a task ID it cannot parse a node out of' do
    stub_request(:put, 'https://pve.example.com:8006/api2/json/cluster/sdn')
      .to_return(status: 200, body: { data: 'not-a-upid' }.to_json)

    output, exit_status = run_and_capture(base_input)

    expect(exit_status).to eq(1)
    expect(JSON.parse(output)['_error']['msg']).to match(%r{unusable task ID})
  end
end
