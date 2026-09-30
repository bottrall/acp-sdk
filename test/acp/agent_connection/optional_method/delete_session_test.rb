# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod::DeleteSession do
  def initialize_response(capabilities)
    ACP::Types::InitializeResponse.new(protocol_version: 1, agent_capabilities: capabilities)
  end

  it 'is advertised when the session delete capability is set' do
    capabilities = ACP::Types::AgentCapabilities.new(
      session_capabilities: ACP::Types::SessionCapabilities.new(delete: ACP::Types::SessionDeleteCapabilities.new)
    )

    assert ACP::AgentConnection::OptionalMethod::DeleteSession.advertised?(initialize_response(capabilities))
  end

  it 'is not advertised when the session delete capability is unset' do
    refute ACP::AgentConnection::OptionalMethod::DeleteSession.advertised?(
      initialize_response(ACP::Types::AgentCapabilities.new)
    )
  end
end
