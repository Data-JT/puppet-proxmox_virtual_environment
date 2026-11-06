# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pve_datacenter_config'

RSpec.describe 'pve_datacenter_config type' do
  let(:type) { Puppet::Type.type(:pve_datacenter_config) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :name as the namevar' do
    expect(type.key_attributes).to include(:name)
  end

  describe 'name attribute' do
    it 'accepts the literal value datacenter' do
      expect { type.new(name: 'datacenter') }.not_to raise_error
    end

    it 'rejects any other title' do
      expect { type.new(name: 'somethingelse') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'defaults to present' do
      expect(type.new(name: 'datacenter')[:ensure].to_s).to eq('present')
    end
  end

  describe 'optional attributes' do
    subject(:resource) do
      type.new(
        name:             'datacenter',
        description:      'Example cluster',
        keyboard:         'de',
        mac_prefix:       'BC:24:11',
        registered_tags:  ['debian', 'ubuntu'],
        delete_properties: ['email_from'],
      )
    end

    it { expect(resource[:description]).to eq('Example cluster') }
    it { expect(resource[:keyboard]).to eq('de') }
    it { expect(resource[:mac_prefix]).to eq('BC:24:11') }
    it { expect(resource[:registered_tags]).to eq(['debian', 'ubuntu']) }
    it { expect(resource[:delete_properties]).to eq(['email_from']) }

    it 'rejects an unknown keyboard layout' do
      expect { type.new(name: 'datacenter', keyboard: 'klingon') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'attributes default to nil when unset' do
    subject(:resource) { type.new(name: 'datacenter') }

    [:description, :keyboard, :language, :console, :mac_prefix, :email_from, :http_proxy, :max_workers, :bwlimit, :migration, :next_id, :crs, :ha, :fencing, :tag_style, :registered_tags,
     :user_tag_access, :u2f, :webauthn, :notify_settings, :consent_text, :delete_properties].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
