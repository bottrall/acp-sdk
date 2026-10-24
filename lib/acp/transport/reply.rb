# frozen_string_literal: true

class ACP::Transport::Reply
  # @dynamic result
  attr_reader :result #: ACP::Transport::_Response

  # @dynamic after
  attr_reader :after #: ^() -> void

  # @rbs result: ACP::Transport::_Response
  # @rbs after: ^() -> void
  # @rbs return: void
  def initialize(result, after:)
    @result = result
    @after = after
    freeze
  end
end
