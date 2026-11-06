# frozen_string_literal: true

require 'spec_helper'
require 'webmock/rspec'
require 'puppet/transport/proxmox_virtual_environment'

RSpec.describe Puppet::Transport::ProxmoxVirtualEnvironment do
  subject(:transport) { described_class.new(context, connection_info) }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext') }
  let(:token_secret_obj) { instance_double('Puppet::Pops::Types::PSensitiveType::Sensitive', unwrap: 'supersecret') }

  let(:connection_info) do
    {
      host:         'pve.example.com',
      port:         8006,
      token_id:     'user@realm!mytoken',
      token_secret: token_secret_obj,
      ssl_verify:   false,
    }
  end

  let(:base_url)     { 'https://pve.example.com:8006/api2/json' }
  let(:auth_header)  { 'PVEAPIToken=user@realm!mytoken=supersecret' }
  let(:json_headers) { { 'Authorization' => auth_header, 'Content-Type' => 'application/json' } }

  before(:each) do
    allow(context).to receive(:debug)
  end

  describe '#get' do
    it 'returns unwrapped data array on success' do
      stub_request(:get, "#{base_url}/storage")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": [{"name": "ds1"}]}')

      expect(transport.get(context, '/storage')).to eq([{ 'name' => 'ds1' }])
    end

    it 'returns unwrapped data hash on success' do
      stub_request(:get, "#{base_url}/version")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": {"version": "2.4.3"}}')

      expect(transport.get(context, '/version')).to eq({ 'version' => '2.4.3' })
    end

    it 'encodes query parameters' do
      stub_request(:get, "#{base_url}/access/acl?exact=1&path=%2Fstorage%2Fbackup")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": []}')

      expect(transport.get(context, '/access/acl', 'exact' => 1, 'path' => '/storage/backup')).to eq([])
    end
  end

  describe '#post' do
    it 'sends request body and returns unwrapped data' do
      stub_request(:post, "#{base_url}/storage")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": null}')

      result = transport.post(context, '/storage', { 'name' => 'ds1', 'path' => '/mnt/ds1' })
      expect(result).to be_nil
    end
  end

  describe '#put' do
    it 'sends request and returns unwrapped data' do
      stub_request(:put, "#{base_url}/storage/ds1")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": null}')

      expect(transport.put(context, '/storage/ds1', { 'comment' => 'updated' })).to be_nil
    end
  end

  describe '#delete' do
    it 'sends request and returns unwrapped data' do
      stub_request(:delete, "#{base_url}/storage/ds1")
        .with(headers: json_headers)
        .to_return(status: 200, body: '{"data": null}')

      expect(transport.delete(context, '/storage/ds1')).to be_nil
    end
  end

  describe '#call' do
    it 'dispatches by HTTP method and expands path parameters' do
      stub_request(:put, "#{base_url}/storage/my%20store")
        .with(headers: json_headers, body: '{"comment":"updated"}')
        .to_return(status: 200, body: '{"data": null}')

      expect(
        transport.call(
          context,
          'PUT',
          '/storage/{name}',
          path_params: { 'name' => 'my store' },
          body:        { 'comment' => 'updated' },
        ),
      ).to be_nil
    end

    it 'raises for unsupported methods' do
      expect { transport.call(context, 'PATCH', '/version') }
        .to raise_error(Puppet::ResourceError, %r{Unsupported PVE API method PATCH})
    end
  end

  describe 'connection info validation' do
    it 'raises naming host when host is missing' do
      info = connection_info.merge(host: nil)
      expect { described_class.new(context, info) }
        .to raise_error(Puppet::ResourceError, %r{host})
    end

    it 'raises naming host when host is empty' do
      info = connection_info.merge(host: '')
      expect { described_class.new(context, info) }
        .to raise_error(Puppet::ResourceError, %r{host})
    end

    it 'raises naming token_id when token_id is missing' do
      info = connection_info.merge(token_id: nil)
      expect { described_class.new(context, info) }
        .to raise_error(Puppet::ResourceError, %r{token_id})
    end

    it 'raises naming token_secret when it unwraps to nil' do
      info = connection_info.merge(token_secret: instance_double('Puppet::Pops::Types::PSensitiveType::Sensitive', unwrap: nil))
      expect { described_class.new(context, info) }
        .to raise_error(Puppet::ResourceError, %r{token_secret})
    end

    it 'raises naming token_secret when it is an empty string' do
      info = connection_info.merge(token_secret: '')
      expect { described_class.new(context, info) }
        .to raise_error(Puppet::ResourceError, %r{token_secret})
    end
  end

  describe 'non-JSON 2xx guard' do
    it 'raises when a 2xx body is not valid JSON' do
      stub_request(:get, "#{base_url}/storage")
        .to_return(status: 200, body: '<html>not json</html>')

      expect { transport.get(context, '/storage') }
        .to raise_error(Puppet::ResourceError, %r{non-JSON response on /storage})
    end

    it 'still raises with the status code when a non-2xx body is not JSON' do
      stub_request(:get, "#{base_url}/storage")
        .to_return(status: 500, body: '<html>server error</html>')

      expect { transport.get(context, '/storage') }
        .to raise_error(Puppet::ResourceError, %r{500})
    end
  end

  describe 'stale keep-alive handling' do
    it 'retries an idempotent GET once after a stale-connection error' do
      stub_request(:get, "#{base_url}/version")
        .to_raise(EOFError).then
        .to_return(status: 200, body: '{"data": {"version": "9.0"}}')

      expect(transport.get(context, '/version')).to eq({ 'version' => '9.0' })
    end

    it 'does not retry a POST and raises a clear connection error' do
      stub_request(:post, "#{base_url}/storage")
        .to_raise(Errno::ECONNRESET)

      expect { transport.post(context, '/storage', { 'name' => 'ds1' }) }
        .to raise_error(Puppet::ResourceError, %r{connection error})
    end
  end

  describe 'error handling' do
    it 'raises Puppet::ResourceError on 401' do
      stub_request(:get, "#{base_url}/storage")
        .to_return(status: 401, body: 'Unauthorized')

      expect { transport.get(context, '/storage') }
        .to raise_error(Puppet::ResourceError, %r{401})
    end

    it 'raises Puppet::ResourceError on 404' do
      stub_request(:get, "#{base_url}/missing")
        .to_return(status: 404, body: 'Not Found')

      expect { transport.get(context, '/missing') }
        .to raise_error(Puppet::ResourceError, %r{404})
    end

    it 'raises Puppet::ResourceError on 500' do
      stub_request(:get, "#{base_url}/storage")
        .to_return(status: 500, body: 'Internal Server Error')

      expect { transport.get(context, '/storage') }
        .to raise_error(Puppet::ResourceError, %r{500})
    end
  end

  describe 'empty response body' do
    it 'returns nil when body is an empty string' do
      stub_request(:delete, "#{base_url}/storage/ds1")
        .to_return(status: 200, body: '')

      expect(transport.delete(context, '/storage/ds1')).to be_nil
    end
  end

  describe 'TLS configuration' do
    let(:ok_response) { instance_double(Net::HTTPResponse, code: '200', body: '{"data": null}') }
    let(:http_double) { instance_double(Net::HTTP) }

    before(:each) do
      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:open_timeout=)
      allow(http_double).to receive(:read_timeout=)
      allow(http_double).to receive(:verify_mode=)
      allow(http_double).to receive(:start)
      allow(http_double).to receive(:request).and_return(ok_response)
    end

    it 'opens connections within 10 seconds and waits up to 60 seconds for a response' do
      expect(http_double).to receive(:open_timeout=).with(10)
      expect(http_double).to receive(:read_timeout=).with(60)
      transport.get(context, '/version')
    end

    it 'sets VERIFY_NONE when ssl_verify is false' do
      expect(http_double).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_NONE)
      transport.get(context, '/version')
    end

    it 'defaults to VERIFY_PEER when ssl_verify is omitted' do
      info = connection_info.reject { |key, _| key == :ssl_verify }
      default_transport = described_class.new(context, info)
      expect(http_double).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
      default_transport.get(context, '/version')
    end

    context 'when ssl_verify is true' do
      let(:connection_info) { super().merge(ssl_verify: true, ssl_ca_file: '/etc/ssl/custom-ca.pem') }

      before(:each) do
        allow(http_double).to receive(:ca_file=)
      end

      it 'sets VERIFY_PEER' do
        expect(http_double).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
        transport.get(context, '/version')
      end

      it 'sets ca_file when ssl_ca_file is provided' do
        expect(http_double).to receive(:ca_file=).with('/etc/ssl/custom-ca.pem')
        transport.get(context, '/version')
      end
    end
  end

  describe 'token_secret handling' do
    it 'accepts a Sensitive-wrapped token_secret' do
      sensitive = instance_double('Puppet::Pops::Types::PSensitiveType::Sensitive', unwrap: 'mytoken')
      info = connection_info.merge(token_secret: sensitive)
      t = described_class.new(context, info)
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data": null}')
      expect { t.get(context, '/version') }.not_to raise_error
    end

    it 'accepts a plain String token_secret (provider-mode without device credentials)' do
      info = connection_info.merge(token_secret: 'plainstring')
      t = described_class.new(context, info)
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data": null}')
      expect { t.get(context, '/version') }.not_to raise_error
    end
  end

  describe 'secret protection in logs' do
    it 'never includes token_secret in any debug output' do
      stub_request(:get, "#{base_url}/storage")
        .to_return(status: 200, body: '{"data": []}')

      logged = []
      allow(context).to receive(:debug) { |msg| logged << msg }

      transport.get(context, '/storage')

      logged.each { |msg| expect(msg).not_to include('supersecret') }
    end

    it 'logs method and path for each request' do
      stub_request(:get, "#{base_url}/storage")
        .to_return(status: 200, body: '{"data": []}')

      logged = []
      allow(context).to receive(:debug) { |msg| logged << msg }

      transport.get(context, '/storage')

      expect(logged).to include(a_string_including('GET', '/storage'))
    end
  end
end
