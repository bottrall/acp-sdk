# frozen_string_literal: true

class ACP::Transport::Reply
  # @dynamic result
  attr_reader :result #: ACP::Transport::Stdio::_ToH

  # @dynamic after
  attr_reader :after #: ^() -> void

  # @rbs result: ACP::Transport::Stdio::_ToH
  # @rbs after: ^() -> void
  # @rbs return: void
  def initialize(result, after:)
    @result = result
    @after = after
    freeze
  end
end
