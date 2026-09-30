# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::ResumeSession
  extend self

  # @rbs return: String
  def rpc_method
    'session/resume'
  end

  # @rbs return: Symbol
  def agent_method
    :resume_session
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    initialize_response.agent_capabilities&.session_capabilities&.resume ? true : false
  end
end
