# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::ForkSession
  extend self

  # @rbs return: String
  def rpc_method
    'session/fork'
  end

  # @rbs return: Symbol
  def agent_method
    :fork_session
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    session = initialize_response.agent_capabilities&.session_capabilities #: ACP::Types::SessionCapabilities | ACP::Types::Unstable::SessionCapabilities?
    fork = session.is_a?(ACP::Types::Unstable::SessionCapabilities) ? session.fork : nil #: ACP::Types::Unstable::SessionForkCapabilities?
    fork ? true : false
  end
end
