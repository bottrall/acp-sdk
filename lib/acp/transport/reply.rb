# frozen_string_literal: true

# A request handler's result plus a callback the transport runs once that
# result is on the wire, for messages the peer must only see after the reply.
class ACP::Transport::Reply
  # @dynamic result
  attr_reader :result #: ACP::Transport::Result

  # @dynamic after
  attr_reader :after #: ^() -> void

  # @rbs result: ACP::Transport::Result
  # @rbs after: ^() -> void
  # @rbs return: void
  def initialize(result, after:)
    @result = result
    @after = after
    freeze
  end
end
