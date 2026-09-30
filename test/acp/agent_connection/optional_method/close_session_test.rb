# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod::CloseSession do
  def initialize_response(capabilities)
    ACP::Types::InitializeResponse.new(protocol_version: 1, agent_capabilities: capabilities)
  end

  it 'is advertised when the session close capability is set' do
    capabilities = ACP::Types::AgentCapabilities.new(
      session_capabilities: ACP::Types::SessionCapabilities.new(close: ACP::Types::SessionCloseCapabilities.new)
    )

    assert ACP::AgentConnection::OptionalMethod::CloseSession.advertised?(initialize_response(capabilities))
  end

  it 'is not advertised when the session close capability is unset' do
    refute ACP::AgentConnection::OptionalMethod::CloseSession.advertised?(
      initialize_response(ACP::Types::AgentCapabilities.new)
    )
  end
end
