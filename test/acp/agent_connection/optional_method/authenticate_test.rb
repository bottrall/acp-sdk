# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod::Authenticate do
  def initialize_response(auth_methods)
    ACP::Types::InitializeResponse.new(protocol_version: 1, auth_methods:)
  end

  it 'is advertised when an auth method is declared' do
    auth_method = ACP::Types::AuthMethodAgent.new(id: 'token', name: 'Token')

    assert ACP::AgentConnection::OptionalMethod::Authenticate.advertised?(initialize_response([auth_method]))
  end

  it 'is not advertised when no auth method is declared' do
    refute ACP::AgentConnection::OptionalMethod::Authenticate.advertised?(initialize_response([]))
  end
end
