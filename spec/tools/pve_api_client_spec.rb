# frozen_string_literal: true

require 'spec_helper'
require_relative '../../tools/pve_hiera_import'

RSpec.describe PveApiClient do
  subject(:client) do
    described_class.new(
      host: 'pve.example.com',
      port: 8006,
      token_id: 'puppet@pve!puppet',
      token_secret: 'secret',
      ssl_verify: false,
    )
  end

  it 'uses the PVE API token authorization format' do
    stub_request(:get, 'https://pve.example.com:8006/api2/json/version')
      .with(headers: { 'Authorization' => 'PVEAPIToken=puppet@pve!puppet=secret' })
      .to_return(status: 200, body: '{"data":{"version":"9.0"}}')

    expect(client.get('/version')).to eq('version' => '9.0')
  end
end
