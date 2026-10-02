# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::Logout
  extend self

  # @rbs return: String
  def rpc_method
    'logout'
  end

  # @rbs return: Symbol
  def agent_method
    :logout
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    initialize_response.agent_capabilities&.auth&.logout ? true : false
  end
end
