# frozen_string_literal: true

class ACP::ClientConnection
  # @rbs @transport: ACP::AgentConnection::_Transport
  # @rbs @permission: ACP::ClientConnection::_PermissionHandler
  # @rbs @read_text_file: (^(ACP::Types::ReadTextFileRequest) -> (ACP::Types::ReadTextFileResponse | ACP::RequestError))?
  # @rbs @write_text_file: (^(ACP::Types::WriteTextFileRequest) -> (ACP::Types::WriteTextFileResponse | ACP::RequestError))?
  # @rbs @updates: ACP::ClientConnection::_UpdateHandler
  # @rbs @fs_capabilities: ACP::Types::FileSystemCapabilities?
  # @rbs @lock: Thread::Mutex
  # @rbs @streams: Hash[String, Thread::Queue]
  # @rbs @pending_permissions: Hash[String, Array[Thread::Queue]]
  # @rbs @logger: ACP::Transport::_Logger

  PROTOCOL_VERSION = ACP::AgentConnection::PROTOCOL_VERSION #: Integer

  IGNORE = ->(_notification) {} #: ^(ACP::Types::SessionNotification) -> void

  CANCELLED = ACP::Types::RequestPermissionResponse.new(
    outcome: ACP::Types::RequestPermissionOutcome::Cancelled.new
  ) #: ACP::Types::RequestPermissionResponse

  # @rbs transport: ACP::AgentConnection::_Transport
  # @rbs permission: ACP::ClientConnection::_PermissionHandler
  # @rbs read_text_file: (^(ACP::Types::ReadTextFileRequest) -> (ACP::Types::ReadTextFileResponse | ACP::RequestError))?
  # @rbs write_text_file: (^(ACP::Types::WriteTextFileRequest) -> (ACP::Types::WriteTextFileResponse | ACP::RequestError))?
  # @rbs updates: ACP::ClientConnection::_UpdateHandler
  # @rbs logger: ACP::Transport::_Logger
  # @rbs return: void
  def initialize(transport:, permission:, read_text_file: nil, write_text_file: nil, updates: IGNORE, logger: ACP::Transport::StderrLogger.new)
    @transport = transport
    @permission = permission
    @read_text_file = read_text_file
    @write_text_file = write_text_file
    @updates = updates
    @fs_capabilities = nil
    @lock = Mutex.new
    @streams = {}
    @pending_permissions = {}
    @logger = logger
  end

  # @rbs return: Thread
  def start
    @transport.start(
      requests: {
        'session/request_permission' => method(:request_permission),
        'fs/read_text_file' => method(:read_text_file),
        'fs/write_text_file' => method(:write_text_file)
      },
      notifications: { 'session/update' => method(:dispatch) }
    )
  end

  # Ruby reserves initialize for the constructor, so the initialize request is
  # sent by connect.
  #
  # @rbs request: ACP::Types::InitializeRequest
  # @rbs return: ACP::Types::InitializeResponse | ACP::RequestError
  def connect(request)
    capabilities = request.client_capabilities&.fs
    unserved = unserved_fs_methods(capabilities)
    unless unserved.empty?
      raise ArgumentError, "initialize advertises fs methods no handler serves: #{unserved.join(', ')}"
    end

    @fs_capabilities = capabilities
    parse(ACP::Types::InitializeResponse, @transport.request('initialize', request.to_h)).then do |response|
      next response if response.is_a?(ACP::RequestError)

      next response if response.protocol_version == PROTOCOL_VERSION

      ACP::RequestError.unsupported_protocol_version(
        requested: request.protocol_version,
        returned: response.protocol_version
      )
    end
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

  # The agent does not replay history on resume, so unlike session_load there
  # is nothing to stream and no block is taken.
  #
  # @rbs request: ACP::Types::ResumeSessionRequest
  # @rbs return: ACP::Types::ResumeSessionResponse | ACP::RequestError
  def session_resume(request)
    parse(ACP::Types::ResumeSessionResponse, @transport.request('session/resume', request.to_h))
  end

  # @rbs request: ACP::Types::CloseSessionRequest
  # @rbs return: ACP::Types::CloseSessionResponse | ACP::RequestError
  def session_close(request)
    parse(ACP::Types::CloseSessionResponse, @transport.request('session/close', request.to_h))
  end

  # @rbs request: ACP::Types::DeleteSessionRequest
  # @rbs return: ACP::Types::DeleteSessionResponse | ACP::RequestError
  def session_delete(request)
    parse(ACP::Types::DeleteSessionResponse, @transport.request('session/delete', request.to_h))
  end

  # The spec requires a pending session/request_permission to be answered with
  # the cancelled outcome once the turn is cancelled, so every queue registered
  # for the session gets one before this returns. The notification goes first
  # so the wire order is cancel, then the cancelled replies.
  #
  # @rbs notification: ACP::Types::CancelNotification
  # @rbs return: void
  def session_cancel(notification)
    @transport.notify('session/cancel', notification.to_h)
    pending = @lock.synchronize { @pending_permissions.delete(notification.session_id) }
    pending&.each { |replies| replies << [:value, CANCELLED] }
  end

  # @rbs request: ACP::Types::SetSessionModeRequest
  # @rbs return: ACP::Types::SetSessionModeResponse | ACP::RequestError
  def session_set_mode(request)
    parse(ACP::Types::SetSessionModeResponse, @transport.request('session/set_mode', request.to_h))
  end

  # The reply carries the session's complete option list, so it replaces any
  # state held from an earlier reply rather than merging into it.
  #
  # @rbs request: ACP::Types::SetSessionConfigOptionRequest
  # @rbs return: ACP::Types::SetSessionConfigOptionResponse | ACP::RequestError
  def session_set_config_option(request)
    parse(ACP::Types::SetSessionConfigOptionResponse, @transport.request('session/set_config_option', request.to_h))
  end

  # @rbs request: ACP::Types::AuthenticateRequest
  # @rbs return: ACP::Types::AuthenticateResponse | ACP::RequestError
  def authenticate(request)
    parse(ACP::Types::AuthenticateResponse, @transport.request('authenticate', request.to_h))
  end

  # @rbs request: ACP::Types::LogoutRequest
  # @rbs return: ACP::Types::LogoutResponse | ACP::RequestError
  def logout(request)
    parse(ACP::Types::LogoutResponse, @transport.request('logout', request.to_h))
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

  # The handler runs on its own thread so a cancelled request is answered
  # without waiting for it, and whatever it returns after that is pushed to a
  # queue nobody reads.
  #
  # @rbs params: untyped
  # @rbs return: (ACP::Types::RequestPermissionResponse | ACP::RequestError)
  def request_permission(params)
    request = ACP::Types::RequestPermissionRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    replies = Thread::Queue.new
    register_permission(request.session_id, replies)
    Thread.new do
      # A raised StandardError is not a returned ACP::RequestError, so the two
      # need distinct shapes on the queue.
      replies << begin
        [:value, @permission.call(request)]
      rescue StandardError => e
        [:raised, e]
      end
    ensure
      unregister_permission(request.session_id, replies)
    end
    settled = replies.pop
    # Re-raised so the transport's invoke turns it into an error reply, as it
    # would if the handler ran on the serve thread itself.
    raise settled[1] if settled[0] == :raise

    settled[1]
  end

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

  # The routes are registered at start, before connect records the advertised
  # capabilities, so each one answers -32601 until then.
  #
  # @rbs params: untyped
  # @rbs return: (ACP::Types::ReadTextFileResponse | ACP::RequestError)
  def read_text_file(params)
    return ACP::RequestError.unadvertised('fs.readTextFile') unless @fs_capabilities&.read_text_file

    request = ACP::Types::ReadTextFileRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    # Safe: connect refuses an advertised capability no handler serves.
    handler = @read_text_file #: ^(ACP::Types::ReadTextFileRequest) -> (ACP::Types::ReadTextFileResponse | ACP::RequestError)
    handler.call(request)
  end

  # @rbs params: untyped
  # @rbs return: (ACP::Types::WriteTextFileResponse | ACP::RequestError)
  def write_text_file(params)
    return ACP::RequestError.unadvertised('fs.writeTextFile') unless @fs_capabilities&.write_text_file

    request = ACP::Types::WriteTextFileRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    # Safe: connect refuses an advertised capability no handler serves.
    handler = @write_text_file #: ^(ACP::Types::WriteTextFileRequest) -> (ACP::Types::WriteTextFileResponse | ACP::RequestError)
    handler.call(request)
  end

  # The fs capabilities initialize advertises that no injected handler serves.
  #
  # @rbs capabilities: ACP::Types::FileSystemCapabilities?
  # @rbs return: Array[String]
  def unserved_fs_methods(capabilities)
    {
      'fs.readTextFile' => capabilities&.read_text_file && !@read_text_file,
      'fs.writeTextFile' => capabilities&.write_text_file && !@write_text_file
    }.select { |_, unserved| unserved }.keys
  end
end
