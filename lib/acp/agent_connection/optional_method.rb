# frozen_string_literal: true

class ACP::AgentConnection::OptionalMethod
  # @rbs @advertised: ^(ACP::Types::InitializeResponse) -> boolish

  # @dynamic rpc_method
  attr_reader :rpc_method #: String

  # @dynamic agent_method
  attr_reader :agent_method #: Symbol

  # @rbs rpc_method: String
  # @rbs agent_method: Symbol
  # @rbs &advertised: (ACP::Types::InitializeResponse) -> boolish
  # @rbs return: void
  def initialize(rpc_method:, agent_method:, &advertised)
    @rpc_method = rpc_method
    @agent_method = agent_method
    @advertised = advertised
    freeze
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    @advertised.call(initialize_response) ? true : false
  end
end
