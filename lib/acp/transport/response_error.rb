# frozen_string_literal: true

class ACP::Transport::ResponseError
  # @dynamic code
  attr_reader :code #: Integer

  # @dynamic message
  attr_reader :message #: String

  # @dynamic data
  attr_reader :data #: untyped

  # @rbs code: Integer
  # @rbs message: String
  # @rbs data: untyped
  # @rbs return: void
  def initialize(code:, message:, data: nil)
    @code = code
    @message = message
    @data = data
    freeze
  end

  # @rbs return: Hash[String, untyped]
  def to_h
    { 'code' => code, 'message' => message, 'data' => data }.compact
  end
end
