# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod::Logout do
  def initialize_response(capabilities)
    ACP::Types::InitializeResponse.new(protocol_version: 1, agent_capabilities: capabilities)
  end

  it 'is advertised when auth logout is declared' do
    capabilities = ACP::Types::AgentCapabilities.new(
      auth: ACP::Types::AgentAuthCapabilities.new(logout: ACP::Types::LogoutCapabilities.new)
    )

    assert ACP::AgentConnection::OptionalMethod::Logout.advertised?(initialize_response(capabilities))
  end

  it 'is not advertised when auth logout is not declared' do
    refute ACP::AgentConnection::OptionalMethod::Logout.advertised?(initialize_response(ACP::Types::AgentCapabilities.new))
  end

  it 'is not advertised when auth is not declared' do
    capabilities = ACP::Types::AgentCapabilities.new(auth: ACP::Types::AgentAuthCapabilities.new)

    refute ACP::AgentConnection::OptionalMethod::Logout.advertised?(initialize_response(capabilities))
  end
end
