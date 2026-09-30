# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod::ListSessions do
  def initialize_response(capabilities)
    ACP::Types::InitializeResponse.new(protocol_version: 1, agent_capabilities: capabilities)
  end

  it 'is advertised when the session list capability is set' do
    capabilities = ACP::Types::AgentCapabilities.new(
      session_capabilities: ACP::Types::SessionCapabilities.new(list: ACP::Types::SessionListCapabilities.new)
    )

    assert ACP::AgentConnection::OptionalMethod::ListSessions.advertised?(initialize_response(capabilities))
  end

  it 'is not advertised when the session list capability is unset' do
    refute ACP::AgentConnection::OptionalMethod::ListSessions.advertised?(
      initialize_response(ACP::Types::AgentCapabilities.new)
    )
  end
end
