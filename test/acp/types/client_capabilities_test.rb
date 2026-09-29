# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::ClientCapabilities do
  let(:payload) do
    {
      'fs' => { 'readTextFile' => true, 'writeTextFile' => false },
      'terminal' => true,
      'session' => { 'configOptions' => { 'boolean' => {} } },
      'auth' => { 'terminal' => true },
      'elicitation' => { 'form' => {}, 'url' => {} }
    }
  end

  it 'round-trips every client capability' do
    assert_equal payload, ACP::Types::ClientCapabilities.from_h(payload).to_h
  end

  it 'builds nested capability structs' do
    capabilities = ACP::Types::ClientCapabilities.from_h(payload)

    assert_instance_of ACP::Types::ElicitationUrlCapabilities, capabilities.elicitation&.url
  end
end
