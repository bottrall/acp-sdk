# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::InitializeRequest do
  let(:payload) do
    {
      'protocolVersion' => 1,
      'clientCapabilities' => {
        'fs' => { 'readTextFile' => true, 'writeTextFile' => true },
        'terminal' => true
      },
      'clientInfo' => { 'name' => 'my-client', 'title' => 'My Client', 'version' => '1.0.0' }
    }
  end

  it 'round-trips the initialize example from the protocol docs' do
    assert_equal payload, ACP::Types::InitializeRequest.from_h(payload).to_h
  end

  it 'builds the client capabilities as typed values' do
    request = ACP::Types::InitializeRequest.from_h(payload)

    assert request.client_capabilities&.fs&.write_text_file
  end
end
