# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require_relative '../../tasks/pve_api_request'

RSpec.describe 'pve_api_request task' do
  # Run the task entry point, capturing stdout and the exit status. A
  # successful run returns exit status 0; a failure raises SystemExit which
  # we translate into its numeric status.
  def run_and_capture(input)
    original = $stdout
    $stdout = StringIO.new
    exit_status = 0
    begin
      run_task(input)
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
      'method' => 'GET',
      'path' => '/version',
      'ssl_verify' => false,
    }.merge(overrides)
  end

  describe '#api_request happy path' do
    it 'uses the PVE API token authorization format' do
      stub_request(:get, 'https://pve.example.com:8006/api2/json/version')
        .with(headers: { 'Authorization' => 'PVEAPIToken=puppet@pve!puppet=secret' })
        .to_return(status: 200, body: '{"data":{"version":"9.0"}}')

      result = api_request(base_input)

      expect(result).to include(status: 200, success: true, data: { 'version' => '9.0' })
    end

    it 'sends a JSON encoded body for POST requests' do
      stub_request(:post, 'https://pve.example.com:8006/api2/json/nodes/pve/qemu')
        .with(
          body: '{"vmid":"100","name":"test"}',
          headers: { 'Content-Type' => 'application/json' },
        )
        .to_return(status: 200, body: '{"data":"UPID:pve:task"}')

      result = api_request(
        base_input(
          'method' => 'POST',
          'path' => '/nodes/pve/qemu',
          'body' => { 'vmid' => '100', 'name' => 'test' },
        ),
      )

      expect(result).to include(status: 200, success: true, data: 'UPID:pve:task')
    end
  end

  describe '#bool' do
    it 'accepts documented truthy and falsey values' do
      expect(bool(true)).to be(true)
      expect(bool('true')).to be(true)
      expect(bool('1')).to be(true)
      expect(bool(1)).to be(true)
      expect(bool(false)).to be(false)
      expect(bool('false')).to be(false)
      expect(bool('0')).to be(false)
      expect(bool(0)).to be(false)
    end

    it 'returns the default for nil' do
      expect(bool(nil, default: true)).to be(true)
      expect(bool(nil, default: false)).to be(false)
    end

    it 'raises ArgumentError on unrecognized values' do
      expect { bool('yes') }.to raise_error(ArgumentError)
      expect { bool('no') }.to raise_error(ArgumentError)
      expect { bool(42) }.to raise_error(ArgumentError)
    end
  end

  describe '#run error contract' do
    it 'emits a Bolt _error and exits non-zero for an unsupported method' do
      output, status = run_and_capture(base_input('method' => 'PATCH'))

      expect(status).not_to eq(0)
      parsed = JSON.parse(output)
      expect(parsed).to have_key('_error')
      expect(parsed['_error']['kind']).to eq('proxmox_virtual_environment/api-error')
      expect(parsed['_error']['msg']).to include('PATCH')
    end

    it 'errors out for an unrecognized ssl_verify instead of disabling TLS verification' do
      output, status = run_and_capture(base_input('ssl_verify' => 'yes'))

      expect(status).not_to eq(0)
      parsed = JSON.parse(output)
      expect(parsed).to have_key('_error')
    end

    it 'reports a non-2xx JSON error body with its HTTP status code' do
      stub_request(:get, 'https://pve.example.com:8006/api2/json/version')
        .to_return(status: 500, body: '{"errors":{"foo":"bar"}}')

      output, status = run_and_capture(base_input)

      expect(status).not_to eq(0)
      parsed = JSON.parse(output)
      expect(parsed['_error']['kind']).to eq('proxmox_virtual_environment/api-error')
      expect(parsed['_error']['details']['status']).to eq(500)
      expect(parsed['_error']['details']['body']).to eq('errors' => { 'foo' => 'bar' })
    end

    it 'reports a non-2xx non-JSON body without crashing on JSON parsing' do
      stub_request(:get, 'https://pve.example.com:8006/api2/json/version')
        .to_return(status: 502, body: '<html><body>Bad Gateway</body></html>')

      output, status = run_and_capture(base_input)

      expect(status).not_to eq(0)
      parsed = JSON.parse(output)
      expect(parsed['_error']['details']['status']).to eq(502)
      expect(parsed['_error']['details']['body']).to include('Bad Gateway')
    end

    it 'emits a Bolt _error and exits non-zero for malformed stdin JSON' do
      allow(STDIN).to receive(:read).and_return('{not valid json')

      output, status = run_and_capture(nil)

      expect(status).not_to eq(0)
      parsed = JSON.parse(output)
      expect(parsed).to have_key('_error')
    end
  end
end
