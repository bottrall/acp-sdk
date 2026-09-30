# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::LoadSession
  # @rbs return: String
  def self.rpc_method
    'session/load'
  end

  # @rbs return: Symbol
  def self.agent_method
    :load_session
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def self.advertised?(initialize_response)
    initialize_response.agent_capabilities&.load_session ? true : false
  end
end
