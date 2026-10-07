# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod::ListProviders
  extend self

  # @rbs return: String
  def rpc_method
    'providers/list'
  end

  # @rbs return: Symbol
  def agent_method
    :list_providers
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    capabilities = initialize_response.agent_capabilities #: ACP::Types::AgentCapabilities | ACP::Types::Unstable::AgentCapabilities?
    providers = capabilities.is_a?(ACP::Types::Unstable::AgentCapabilities) ? capabilities.providers : nil #: ACP::Types::Unstable::ProvidersCapabilities?
    providers ? true : false
  end
end
