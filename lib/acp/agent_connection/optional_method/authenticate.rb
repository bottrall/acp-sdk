# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::Authenticate
  # @rbs return: String
  def self.rpc_method
    'authenticate'
  end

  # @rbs return: Symbol
  def self.agent_method
    :authenticate
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def self.advertised?(initialize_response)
    initialize_response.auth_methods&.any? || false
  end
end
