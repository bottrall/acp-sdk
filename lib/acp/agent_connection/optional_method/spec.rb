# frozen_string_literal: true

class ACP::AgentConnection::OptionalMethod::Spec
  # @dynamic rpc_method
  attr_reader :rpc_method #: String
  # @dynamic agent_method
  attr_reader :agent_method #: Symbol
  # @dynamic path
  attr_reader :path #: Array[Symbol]

  # @rbs rpc_method: String
  # @rbs agent_method: Symbol
  # @rbs path: Array[Symbol]
  # @rbs return: void
  def initialize(rpc_method:, agent_method:, path:)
    @rpc_method = rpc_method
    @agent_method = agent_method
    @path = path.freeze
    freeze
  end

  # Readers missing along the chain count as unadvertised, so the stable
  # capabilities answer false for the unstable-only paths (fork, providers).
  #
  # @rbs initialize_response: ACP::Types::InitializeResponse
  # @rbs return: bool
  def advertised?(initialize_response)
    # reduce's U pins to the InitializeResponse argument, but the chain walks
    # through unrelated capability types.
    value = path.reduce(initialize_response) { |node, name| follow(node, name) } #: untyped
    value ? true : false
  end

  private

  # @rbs node: untyped
  # @rbs name: Symbol
  # @rbs return: untyped
  def follow(node, name)
    node.respond_to?(name) ? node.public_send(name) : nil
  end
end
