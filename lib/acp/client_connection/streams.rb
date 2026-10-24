# frozen_string_literal: true

class ACP::ClientConnection::Streams
  CANCELLED = ACP::Types::RequestPermissionResponse.new(
    outcome: ACP::Types::RequestPermissionOutcome::Cancelled.new
  ) #: ACP::Types::RequestPermissionResponse

  # @rbs @sender: ACP::Transport::Stdio
  # @rbs @permission: ACP::ClientConnection::_PermissionHandler
  # @rbs @updates: ACP::ClientConnection::_UpdateHandler
  # @rbs @logger: ACP::Transport::_Logger
  # @rbs @lock: Thread::Mutex
  # @rbs @streams: Hash[String, Thread::Queue]
  # @rbs @pending_permissions: Hash[String, Array[Thread::Queue]]

  # @rbs sender: ACP::Transport::Stdio
  # @rbs permission: ACP::ClientConnection::_PermissionHandler
  # @rbs updates: ACP::ClientConnection::_UpdateHandler
  # @rbs logger: ACP::Transport::_Logger
  # @rbs return: void
  def initialize(sender:, permission:, updates:, logger:)
    @sender = sender
    @permission = permission
    @updates = updates
    @logger = logger
    @lock = Mutex.new
    @streams = {}
    @pending_permissions = {}
  end

  # The request waits on its own thread so the caller's thread can yield each
  # update as it arrives. The reader thread queues an update before it settles
  # a reply sent after it, so the queue closes only after the last one.
  #
  # @rbs session_id: String
  # @rbs method: String
  # @rbs params: Hash[String, untyped]
  # @rbs &block: (ACP::Types::SessionUpdate::t) -> void
  # @rbs return: (Hash[String, untyped] | ACP::RequestError)
  def stream(session_id, method, params, &)
    queue = Thread::Queue.new
    # The check and the insert share one lock acquisition so a concurrent
    # stream cannot register between them.
    claimed = @lock.synchronize do
      if @streams.key?(session_id)
        false
      else
        @streams[session_id] = queue
        true
      end
    end
    unless claimed
      return ACP::RequestError.new(
        code: ACP::RequestError::INVALID_REQUEST, message: "A stream is already open for session #{session_id}"
      )
    end
    requester = Thread.new do
      @sender.request(method, params)
    ensure
      @lock.synchronize { @streams.delete(session_id)&.close }
    end
    while (update = queue.pop)
      yield update
    end
    requester.value
  end

  # Pushes under the lock so a stream cannot close its queue between the
  # lookup and the push. A malformed notification has no reply to carry the
  # failure.
  #
  # @rbs params: untyped
  # @rbs return: void
  def dispatch(params)
    notification = ACP::Types.parse(ACP::Types::SessionNotification, params)
    if notification.is_a?(ACP::Types::ParseError)
      @logger.warn("dropped malformed session/update: #{notification.message}")
    else
      queue = @lock.synchronize { @streams[notification.session_id]&.push(notification.update) }
      @updates.call(notification) unless queue
    end
  end

  # The handler runs on its own thread so a cancelled request is answered
  # without waiting for it, and whatever it returns after that is pushed to a
  # queue nobody reads.
  #
  # @rbs params: untyped
  # @rbs return: (ACP::Types::RequestPermissionResponse | ACP::RequestError)
  def request_permission(params)
    request = ACP::Types.parse(ACP::Types::RequestPermissionRequest, params)
    return ACP::RequestError.invalid_params([request.message]) if request.is_a?(ACP::Types::ParseError)

    replies = Thread::Queue.new
    register_permission(request.session_id, replies)
    # The handler runs on the transport's serve thread, so the serving
    # identity must be carried over for cancelled? to see the cancel there.
    serving = @sender.cancellation
    Thread.new do
      ACP::Transport::Cancellation.current = serving
      replies << begin
        @permission.call(request)
      rescue StandardError => e
        e
      end
    ensure
      unregister_permission(request.session_id, replies)
    end
    settled = replies.pop
    # A handler answers with a response or an ACP::RequestError, neither of
    # them an exception, so one on the queue was raised. Re-raised so the
    # transport's invoke turns it into an error reply, as it would if the
    # handler ran on the serve thread itself.
    raise settled if settled.is_a?(StandardError)

    settled
  end

  # The spec requires a pending session/request_permission to be answered with
  # the cancelled outcome once the turn is cancelled, so every queue registered
  # for the session gets one before this returns.
  #
  # @rbs session_id: String
  # @rbs return: void
  def cancel(session_id)
    pending = @lock.synchronize { @pending_permissions.delete(session_id) }
    pending&.each { |replies| replies << CANCELLED }
  end

  private

  # @rbs session_id: String
  # @rbs replies: Thread::Queue
  # @rbs return: void
  def register_permission(session_id, replies)
    @lock.synchronize { (@pending_permissions[session_id] ||= []) << replies }
  end

  # @rbs session_id: String
  # @rbs replies: Thread::Queue
  # @rbs return: void
  def unregister_permission(session_id, replies)
    @lock.synchronize do
      pending = @pending_permissions[session_id]
      if pending
        pending.delete(replies)
        @pending_permissions.delete(session_id) if pending.empty?
      end
    end
  end
end
