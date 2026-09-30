# frozen_string_literal: true

class ACP::AgentConnection::OptionalMethod
  # @rbs @capability: ^(ACP::Types::AgentCapabilities) -> boolish

  # @dynamic rpc_method
  attr_reader :rpc_method #: String

  # @dynamic agent_method
  attr_reader :agent_method #: Symbol

  # @rbs rpc_method: String
  # @rbs agent_method: Symbol
  # @rbs &capability: (ACP::Types::AgentCapabilities) -> boolish
  # @rbs return: void
  def initialize(rpc_method:, agent_method:, &capability)
    @rpc_method = rpc_method
    @agent_method = agent_method
    @capability = capability
    freeze
  end

  # @rbs capabilities: ACP::Types::AgentCapabilities
  # @rbs return: bool
  def advertised?(capabilities)
    @capability.call(capabilities) ? true : false
  end
end
