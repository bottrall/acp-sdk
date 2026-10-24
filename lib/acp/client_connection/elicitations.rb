# frozen_string_literal: true

class ACP::ClientConnection::Elicitations
  # @rbs @handler: ACP::ClientConnection::_Elicitation?
  # @rbs @logger: ACP::Transport::_Logger
  # @rbs @lock: Thread::Mutex
  # @rbs @outstanding: Hash[String, bool]

  # @rbs handler: ACP::ClientConnection::_Elicitation?
  # @rbs logger: ACP::Transport::_Logger
  # @rbs return: void
  def initialize(handler:, logger:)
    @handler = handler
    @logger = logger
    @lock = Mutex.new
    @outstanding = {}
  end

  # @rbs elicitation_id: String
  # @rbs return: void
  def register(elicitation_id)
    @lock.synchronize { @outstanding[elicitation_id] = true }
  end

  # The spec requires a completion for an unknown or already-completed
  # elicitation id to be ignored, so only an id registered by a served
  # url-mode request reaches the handler. It runs on the transport's reader
  # thread, so it must return quickly.
  #
  # @rbs params: untyped
  # @rbs return: void
  def complete(params)
    notification = ACP::Types.parse(ACP::Types::CompleteElicitationNotification, params)
    if notification.is_a?(ACP::Types::ParseError)
      @logger.warn("dropped malformed elicitation/complete: #{notification.message}")
    else
      known = @lock.synchronize { @outstanding.delete(notification.elicitation_id) }
      handler = @handler
      return unless known && handler

      handler.complete_elicitation(notification) if handler.respond_to?(:complete_elicitation)
    end
  end
end
