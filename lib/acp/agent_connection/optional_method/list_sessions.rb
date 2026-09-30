# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::ListSessions
  # @rbs return: String
  def self.rpc_method
    'session/list'
  end

  # @rbs return: Symbol
  def self.agent_method
    :list_sessions
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def self.advertised?(initialize_response)
    initialize_response.agent_capabilities&.session_capabilities&.list ? true : false
  end
end
