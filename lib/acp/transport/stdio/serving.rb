# frozen_string_literal: true

class ACP::Transport::Stdio::Serving
  # @dynamic id
  attr_reader :id #: untyped

  # @dynamic cancellation
  attr_reader :cancellation #: ACP::Transport::Cancellation

  # @rbs id: untyped
  # @rbs cancellation: ACP::Transport::Cancellation
  # @rbs return: void
  def initialize(id:, cancellation:)
    @id = id
    @cancellation = cancellation
    freeze
  end
end
