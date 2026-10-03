# frozen_string_literal: true

class ACP::ClientConnection
  # @rbs @transport: ACP::AgentConnection::_Transport
  # @rbs @permission: ACP::ClientConnection::_PermissionHandler
  # @rbs @updates: ACP::ClientConnection::_UpdateHandler
  # @rbs @lock: Thread::Mutex
  # @rbs @streams: Hash[String, Thread::Queue]
  # @rbs @logger: ACP::Transport::_Logger

  IGNORE = ->(_notification) {} #: ^(ACP::Types::SessionNotification) -> void

  # @rbs transport: ACP::AgentConnection::_Transport
  # @rbs permission: ACP::ClientConnection::_PermissionHandler
  # @rbs updates: ACP::ClientConnection::_UpdateHandler
  # @rbs logger: ACP::Transport::_Logger
  # @rbs return: void
  def initialize(transport:, permission:, updates: IGNORE, logger: ACP::Transport::StderrLogger.new)
    @transport = transport
    @permission = permission
    @updates = updates
    @lock = Mutex.new
    @streams = {}
    @logger = logger
  end

  # @rbs return: Thread
  def start
    @transport.start(
      requests: { 'session/request_permission' => method(:request_permission) },
      notifications: { 'session/update' => method(:dispatch) }
    )
  end

  # Ruby reserves initialize for the constructor, so the initialize request is
  # sent by connect.
  #
  # @rbs request: ACP::Types::InitializeRequest
  # @rbs return: ACP::Types::InitializeResponse | ACP::RequestError
  def connect(request)
    parse(ACP::Types::InitializeResponse, @transport.request('initialize', request.to_h))
  end

  # @rbs request: ACP::Types::NewSessionRequest
  # @rbs return: ACP::Types::NewSessionResponse | ACP::RequestError
  def session_new(request)
    parse(ACP::Types::NewSessionResponse, @transport.request('session/new', request.to_h))
  end

  # @rbs request: ACP::Types::PromptRequest
  # @rbs &block: (ACP::Types::SessionUpdate::t) -> void
  # @rbs return: ACP::Types::PromptResponse | ACP::RequestError
  def session_prompt(request, &)
    parse(ACP::Types::PromptResponse, stream(request.session_id, 'session/prompt', request.to_h, &))
  end

  # @rbs request: ACP::Types::LoadSessionRequest
  # @rbs &block: (ACP::Types::SessionUpdate::t) -> void
  # @rbs return: ACP::Types::LoadSessionResponse | ACP::RequestError
  def session_load(request, &)
    parse(ACP::Types::LoadSessionResponse, stream(request.session_id, 'session/load', request.to_h, &))
  end

  # @rbs request: ACP::Types::ListSessionsRequest
  # @rbs return: ACP::Types::ListSessionsResponse | ACP::RequestError
  def session_list(request)
    parse(ACP::Types::ListSessionsResponse, @transport.request('session/list', request.to_h))
  end

  # @rbs notification: ACP::Types::CancelNotification
  # @rbs return: void
  def session_cancel(notification)
    @transport.notify('session/cancel', notification.to_h)
  end

  private

  # @rbs type: ACP::AgentConnection::_Parser
  # @rbs result: (Hash[String, untyped] | ACP::RequestError)
  # @rbs return: untyped
  def parse(type, result)
    return result if result.is_a?(ACP::RequestError)

    type.from_h(result)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_response(result)
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
  def stream(session_id, method, params)
    queue = Thread::Queue.new
    @lock.synchronize { @streams[session_id] = queue }
    requester = Thread.new do
      @transport.request(method, params)
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
    notification = ACP::Types::SessionNotification.from_h(params)
  rescue KeyError, TypeError, NoMethodError => e
    @logger.warn("dropped malformed session/update: #{e.class}: #{e.message}")
  else
    queue = @lock.synchronize { @streams[notification.session_id]&.push(notification.update) }
    @updates.call(notification) unless queue
  end

  # @rbs params: untyped
  # @rbs return: (ACP::Types::RequestPermissionResponse | ACP::RequestError)
  def request_permission(params)
    request = ACP::Types::RequestPermissionRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    @permission.call(request)
  end
end
