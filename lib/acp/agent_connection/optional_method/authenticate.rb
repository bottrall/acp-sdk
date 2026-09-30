# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::Authenticate
  extend self

  # @rbs return: String
  def rpc_method
    'authenticate'
  end

  # @rbs return: Symbol
  def agent_method
    :authenticate
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    initialize_response.auth_methods&.any? || false
  end
end
