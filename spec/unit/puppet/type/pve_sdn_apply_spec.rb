# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_sdn_apply'

RSpec.describe 'pve_sdn_apply type' do
  let(:type) { Puppet::Type.type(:pve_sdn_apply) }

  it 'is a singleton keyed by name' do
    expect(type.key_attributes).to eq([:name])
  end

  it "accepts only the title 'sdn'" do
    expect { type.new(name: 'sdn') }.not_to raise_error
    expect { type.new(name: 'something-else') }.to raise_error(Puppet::ResourceError)
  end

  it 'defaults to requiring the configuration to be applied' do
    expect(type.new(name: 'sdn')[:applied]).to eq(:true)
  end

  it 'waits for the apply worker by default' do
    expect(type.new(name: 'sdn')[:wait]).to be(true)
  end

  it 'defaults the wait timeout to five minutes' do
    expect(type.new(name: 'sdn')[:timeout]).to eq(300)
  end

  it 'exposes wait and timeout as parameters, not properties' do
    expect(type.attrtype(:wait)).to eq(:param)
    expect(type.attrtype(:timeout)).to eq(:param)
  end

  it 'exposes pending_objects as read-only' do
    expect(type.type_definition.attributes[:pending_objects][:behaviour]).to eq(:read_only)
  end

  # Detect-only mode is Puppet's own noop metaparameter rather than a bespoke
  # flag, so a run reports the pending change and never applies it.
  it 'supports noop for a report-only apply' do
    expect(type.new(name: 'sdn', noop: true).noop).to be true
  end

  # Declared as an autobefore on each SDN object type rather than an
  # autorequire here: that direction needs no catalog scan, because this type
  # is a singleton whose title is always 'sdn'.
  describe 'ordering' do
    [:pve_sdn_zone, :pve_sdn_vnet, :pve_sdn_subnet, :pve_sdn_controller, :pve_sdn_ipam, :pve_sdn_dns].each do |sdn_type|
      it "runs after #{sdn_type}" do
        require "puppet/type/#{sdn_type}"
        before_types = []
        Puppet::Type.type(sdn_type).eachautobefore { |target, _block| before_types << target }
        expect(before_types).to include(:pve_sdn_apply)
      end
    end
  end
end
