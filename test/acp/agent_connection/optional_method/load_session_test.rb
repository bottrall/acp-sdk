# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod::LoadSession do
  def initialize_response(capabilities)
    ACP::Types::InitializeResponse.new(protocol_version: 1, agent_capabilities: capabilities)
  end

  it 'is advertised when the load_session capability is set' do
    assert ACP::AgentConnection::OptionalMethod::LoadSession.advertised?(
      initialize_response(ACP::Types::AgentCapabilities.new(load_session: true))
    )
  end

  it 'is not advertised when the load_session capability is unset' do
    refute ACP::AgentConnection::OptionalMethod::LoadSession.advertised?(
      initialize_response(ACP::Types::AgentCapabilities.new)
    )
  end
end
