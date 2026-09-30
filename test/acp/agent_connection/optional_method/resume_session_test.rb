# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod::ResumeSession do
  def initialize_response(capabilities)
    ACP::Types::InitializeResponse.new(protocol_version: 1, agent_capabilities: capabilities)
  end

  it 'is advertised when the session resume capability is set' do
    capabilities = ACP::Types::AgentCapabilities.new(
      session_capabilities: ACP::Types::SessionCapabilities.new(resume: ACP::Types::SessionResumeCapabilities.new)
    )

    assert ACP::AgentConnection::OptionalMethod::ResumeSession.advertised?(initialize_response(capabilities))
  end

  it 'is not advertised when the session resume capability is unset' do
    refute ACP::AgentConnection::OptionalMethod::ResumeSession.advertised?(
      initialize_response(ACP::Types::AgentCapabilities.new)
    )
  end
end
