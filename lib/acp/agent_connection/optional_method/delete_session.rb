# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::DeleteSession
  extend self

  # @rbs return: String
  def rpc_method
    'session/delete'
  end

  # @rbs return: Symbol
  def agent_method
    :delete_session
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    initialize_response.agent_capabilities&.session_capabilities&.delete ? true : false
  end
end
