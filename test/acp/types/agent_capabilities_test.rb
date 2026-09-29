# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::AgentCapabilities do
  let(:payload) do
    {
      'loadSession' => true,
      'promptCapabilities' => { 'image' => true, 'audio' => true, 'embeddedContext' => true },
      'mcpCapabilities' => { 'http' => true, 'sse' => true },
      'sessionCapabilities' => {
        'list' => {},
        'delete' => {},
        'additionalDirectories' => {},
        'resume' => {},
        'close' => {}
      },
      'auth' => { 'logout' => {} },
      '_meta' => { 'vendor.example/feature' => true }
    }
  end

  it 'round-trips every agent capability' do
    assert_equal payload, ACP::Types::AgentCapabilities.from_h(payload).to_h
  end

  it 'builds nested capability structs' do
    capabilities = ACP::Types::AgentCapabilities.from_h(payload)

    assert_instance_of ACP::Types::SessionResumeCapabilities, capabilities.session_capabilities&.resume
  end

  it 'leaves unadvertised capabilities nil' do
    assert_nil ACP::Types::AgentCapabilities.from_h({}).load_session
  end
end
