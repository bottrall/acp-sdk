# frozen_string_literal: true

class ACP::ClientConnection::Inbound::Route
  # @dynamic rpc_method
  attr_reader :rpc_method #: String
  # @dynamic type
  attr_reader :type #: ACP::Transport::_Parser
  # @dynamic handler_method
  attr_reader :handler_method #: Symbol
  # @dynamic path
  attr_reader :path #: Array[Symbol]
  # @dynamic capability
  attr_reader :capability #: String

  # @rbs rpc_method: String
  # @rbs type: ACP::Transport::_Parser
  # @rbs handler_method: Symbol
  # @rbs path: Array[Symbol]
  # @rbs capability: String
  # @rbs return: void
  def initialize(rpc_method:, type:, handler_method:, path:, capability:)
    @rpc_method = rpc_method
    @type = type
    @handler_method = handler_method
    @path = path.freeze
    @capability = capability
    freeze
  end
end
