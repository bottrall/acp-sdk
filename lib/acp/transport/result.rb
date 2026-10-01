# frozen_string_literal: true

class ACP::Transport::Result
  # @dynamic value
  attr_reader :value #: untyped

  # @dynamic error
  attr_reader :error #: ACP::RequestError?

  # @rbs value: untyped
  # @rbs return: ACP::Transport::Result
  def self.ok(value)
    new(value:, error: nil)
  end

  # @rbs error: ACP::RequestError
  # @rbs return: ACP::Transport::Result
  def self.error(error)
    new(value: nil, error:)
  end

  # @rbs value: untyped
  # @rbs error: ACP::RequestError?
  # @rbs return: void
  def initialize(value:, error:)
    @value = value
    @error = error
    freeze
  end

  # @rbs return: bool
  def ok?
    error.nil?
  end
end
