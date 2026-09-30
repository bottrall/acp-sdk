# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::LoadSession
  extend self

  # @rbs return: String
  def rpc_method
    'session/load'
  end

  # @rbs return: Symbol
  def agent_method
    :load_session
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    initialize_response.agent_capabilities&.load_session ? true : false
  end
end
