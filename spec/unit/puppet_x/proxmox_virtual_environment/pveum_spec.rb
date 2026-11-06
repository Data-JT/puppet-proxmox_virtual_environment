# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/proxmox_virtual_environment/pveum'

RSpec.describe PuppetX::ProxmoxVirtualEnvironment::Pveum do
  let(:success) { instance_double('Process::Status', success?: true, exitstatus: 0) }
  let(:failure) { instance_double('Process::Status', success?: false, exitstatus: 2) }

  describe '.set_password' do
    # PVE::PTY::read_password verifies, so once is not enough: verified on PVE
    # 9.2.6 that a single write exits 255 with "EOF while reading password".
    it 'writes the password twice on stdin, never in argv' do
      expect(Open3).to receive(:capture2e)
        .with('pveum', 'passwd', 'bob@pve', stdin_data: "s3cret\ns3cret\n")
        .and_return(['', success])
      described_class.set_password('bob@pve', 's3cret')
    end

    it 'raises with the exit status and stderr when pveum fails' do
      allow(Open3).to receive(:capture2e).and_return(['permission denied', failure])
      expect { described_class.set_password('bob@pve', 's3cret') }
        .to raise_error(Puppet::ResourceError, %r{exit 2.*permission denied})
    end

    it 'scrubs the password out of the failure message' do
      allow(Open3).to receive(:capture2e).and_return(['bad password s3cret rejected', failure])
      expect { described_class.set_password('bob@pve', 's3cret') }
        .to raise_error(Puppet::ResourceError) { |error|
              expect(error.message).not_to include('s3cret')
              expect(error.message).to include('[redacted]')
            }
    end

    it 'fails closed with an actionable message when pveum is not installed' do
      allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT, 'pveum')
      expect { described_class.set_password('bob@pve', 's3cret') }
        .to raise_error(Puppet::ResourceError, %r{pveum.*PVE node}m)
    end

    it 'unwraps a Sensitive password' do
      wrapped = Puppet::Pops::Types::PSensitiveType::Sensitive.new('s3cret')
      expect(Open3).to receive(:capture2e)
        .with('pveum', 'passwd', 'bob@pve', stdin_data: "s3cret\ns3cret\n")
        .and_return(['', success])
      described_class.set_password('bob@pve', wrapped)
    end
  end
end
