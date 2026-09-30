# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::CloseSession
  extend self

  # @rbs return: String
  def rpc_method
    'session/close'
  end

  # @rbs return: Symbol
  def agent_method
    :close_session
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    initialize_response.agent_capabilities&.session_capabilities&.close ? true : false
  end
end
