# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod do
  let(:load_session) do
    ACP::AgentConnection::OptionalMethod.new(rpc_method: 'session/load', agent_method: :load_session) do |advertised|
      advertised.agent_capabilities&.load_session
    end
  end

  def initialize_response(capabilities)
    ACP::Types::InitializeResponse.new(protocol_version: 1, agent_capabilities: capabilities)
  end

  it 'is advertised when the initialize response sets its capability' do
    assert load_session.advertised?(initialize_response(ACP::Types::AgentCapabilities.new(load_session: true)))
  end

  it 'is not advertised when the initialize response leaves its capability unset' do
    refute load_session.advertised?(initialize_response(ACP::Types::AgentCapabilities.new))
  end
end
