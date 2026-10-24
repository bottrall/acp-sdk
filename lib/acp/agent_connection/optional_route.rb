# frozen_string_literal: true

class ACP::AgentConnection::OptionalRoute
  # @dynamic rpc_method
  attr_reader :rpc_method #: String
  # @dynamic type
  attr_reader :type #: ACP::Transport::_Parser
  # @dynamic agent_method
  attr_reader :agent_method #: Symbol
  # @dynamic path
  attr_reader :path #: Array[Symbol]?
  # @dynamic handle
  attr_reader :handle #: ^(ACP::AgentConnection::_FullAgent, untyped) -> (ACP::Transport::_Response | ACP::RequestError)

  # @rbs rpc_method: String
  # @rbs type: ACP::Transport::_Parser
  # @rbs agent_method: Symbol
  # @rbs path: Array[Symbol]?
  # @rbs &handle: (ACP::AgentConnection::_FullAgent, untyped) -> (ACP::Transport::_Response | ACP::RequestError)
  # @rbs return: void
  def initialize(rpc_method:, type:, agent_method:, path:, &handle)
    @rpc_method = rpc_method
    @type = type
    @agent_method = agent_method
    @path = path&.freeze
    @handle = handle
    freeze
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    steps = path
    steps ? ACP::Protocol.advertised?(initialize_response, steps) : false
  end

  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs return: bool
  def routed?(initialize_response, agent)
    # The schema gives a per-session method no initialize capability, since an
    # agent offers it in its session responses.
    path ? advertised?(initialize_response) : agent.respond_to?(agent_method)
  end
end
