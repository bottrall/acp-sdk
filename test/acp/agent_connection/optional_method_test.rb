# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod do
  let(:load_session) do
    ACP::AgentConnection::OptionalMethod.new(rpc_method: 'session/load', agent_method: :load_session, &:load_session)
  end

  it 'is advertised when the capabilities set its capability' do
    assert load_session.advertised?(ACP::Types::AgentCapabilities.new(load_session: true))
  end

  it 'is not advertised when the capabilities leave its capability unset' do
    refute load_session.advertised?(ACP::Types::AgentCapabilities.new)
  end
end
