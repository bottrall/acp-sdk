# frozen_string_literal: true

class ACP::ClientConnection
  # @rbs @transport: ACP::AgentConnection::_Transport
  # @rbs @permission: ACP::ClientConnection::_PermissionHandler
  # @rbs @read_text_file: (^(ACP::Types::ReadTextFileRequest) -> (ACP::Types::ReadTextFileResponse | ACP::RequestError))?
  # @rbs @write_text_file: (^(ACP::Types::WriteTextFileRequest) -> (ACP::Types::WriteTextFileResponse | ACP::RequestError))?
  # @rbs @create_terminal: (^(ACP::Types::CreateTerminalRequest) -> (ACP::Types::CreateTerminalResponse | ACP::RequestError))?
  # @rbs @terminal_output: (^(ACP::Types::TerminalOutputRequest) -> (ACP::Types::TerminalOutputResponse | ACP::RequestError))?
  # @rbs @wait_for_terminal_exit: (^(ACP::Types::WaitForTerminalExitRequest) ->
  #   (ACP::Types::WaitForTerminalExitResponse | ACP::RequestError))?
  # @rbs @kill_terminal: (^(ACP::Types::KillTerminalRequest) -> (ACP::Types::KillTerminalResponse | ACP::RequestError))?
  # @rbs @release_terminal: (^(ACP::Types::ReleaseTerminalRequest) -> (ACP::Types::ReleaseTerminalResponse | ACP::RequestError))?
  # @rbs @elicitation: (^(ACP::Types::CreateElicitationRequest) ->
  #   (ACP::Types::CreateElicitationResponse | ACP::RequestError))?
  # @rbs @complete_elicitation: (^(ACP::Types::CompleteElicitationNotification) -> void)?
  # @rbs @updates: ACP::ClientConnection::_UpdateHandler
  # @rbs @mcp_message: (^(ACP::Types::Unstable::MessageMcpRequest) ->
  #   (ACP::Types::Unstable::MessageMcpResponse::t | ACP::RequestError))?
  # @rbs @mcp_advertised: bool?
  # @rbs @fs_capabilities: ACP::Types::FileSystemCapabilities?
  # @rbs @terminal: bool?
  # @rbs @elicitation_capabilities: ACP::Types::ElicitationCapabilities?
  # @rbs @extension_requests: Hash[String, ^(untyped) -> untyped]
  # @rbs @extension_notifications: Hash[String, ^(untyped) -> void]
  # @rbs @lock: Thread::Mutex
  # @rbs @streams: Hash[String, Thread::Queue]
  # @rbs @pending_permissions: Hash[String, Array[Thread::Queue]]
  # @rbs @outstanding_elicitations: Hash[String, bool]
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
  # @rbs create_terminal: (^(ACP::Types::CreateTerminalRequest) -> (ACP::Types::CreateTerminalResponse | ACP::RequestError))?
  # @rbs terminal_output: (^(ACP::Types::TerminalOutputRequest) -> (ACP::Types::TerminalOutputResponse | ACP::RequestError))?
  # @rbs wait_for_terminal_exit: (^(ACP::Types::WaitForTerminalExitRequest) ->
  #   (ACP::Types::WaitForTerminalExitResponse | ACP::RequestError))?
  # @rbs kill_terminal: (^(ACP::Types::KillTerminalRequest) -> (ACP::Types::KillTerminalResponse | ACP::RequestError))?
  # @rbs release_terminal: (^(ACP::Types::ReleaseTerminalRequest) -> (ACP::Types::ReleaseTerminalResponse | ACP::RequestError))?
  # @rbs elicitation: (^(ACP::Types::CreateElicitationRequest) ->
  #   (ACP::Types::CreateElicitationResponse | ACP::RequestError))?
  # @rbs complete_elicitation: (^(ACP::Types::CompleteElicitationNotification) -> void)?
  # @rbs updates: ACP::ClientConnection::_UpdateHandler
  # @rbs mcp_message: (^(ACP::Types::Unstable::MessageMcpRequest) ->
  #   (ACP::Types::Unstable::MessageMcpResponse::t | ACP::RequestError))?
  # @rbs extension_requests: Hash[String, ^(untyped) -> untyped]
  # @rbs extension_notifications: Hash[String, ^(untyped) -> void]
  # @rbs logger: ACP::Transport::_Logger
  # @rbs return: void
  def initialize(
    transport:,
    permission:,
    read_text_file: nil,
    write_text_file: nil,
    create_terminal: nil,
    terminal_output: nil,
    wait_for_terminal_exit: nil,
    kill_terminal: nil,
    release_terminal: nil,
    elicitation: nil,
    complete_elicitation: nil,
    updates: IGNORE,
    mcp_message: nil,
    extension_requests: {},
    extension_notifications: {},
    logger: ACP::Transport::StderrLogger.new
  )
    @transport = transport
    @permission = permission
    @read_text_file = read_text_file
    @write_text_file = write_text_file
    @create_terminal = create_terminal
    @terminal_output = terminal_output
    @wait_for_terminal_exit = wait_for_terminal_exit
    @kill_terminal = kill_terminal
    @release_terminal = release_terminal
    @elicitation = elicitation
    @complete_elicitation = complete_elicitation
    @updates = updates
    @mcp_message = mcp_message
    @mcp_advertised = nil
    @fs_capabilities = nil
    @terminal = nil
    @elicitation_capabilities = nil
    @extension_requests = extension_requests
    @extension_notifications = extension_notifications
    extension_requests.each_key { |name| ACP::Extensions.validate_name(name) }
    extension_notifications.each_key { |name| ACP::Extensions.validate_name(name) }
    @lock = Mutex.new
    @streams = {}
    @pending_permissions = {}
    @outstanding_elicitations = {}
    @logger = logger
  end

  # @rbs return: Thread
  def start
    @transport.start(
      requests: {
        'session/request_permission' => method(:request_permission),
        'fs/read_text_file' => method(:read_text_file),
        'fs/write_text_file' => method(:write_text_file),
        'terminal/create' => method(:create_terminal),
        'terminal/output' => method(:terminal_output),
        'terminal/wait_for_exit' => method(:wait_for_terminal_exit),
        'terminal/kill' => method(:kill_terminal),
        'terminal/release' => method(:release_terminal),
        'elicitation/create' => method(:create_elicitation)
      }.merge(mcp_requests).merge(@extension_requests),
      notifications: { 'session/update' => method(:dispatch),
                       'elicitation/complete' => method(:complete_elicitation) }.merge(@extension_notifications)
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

    terminal = request.client_capabilities&.terminal
    unserved = unserved_terminal_methods(terminal)
    unless unserved.empty?
      raise ArgumentError, "initialize advertises terminal methods no handler serves: #{unserved.join(', ')}"
    end

    elicitation = request.client_capabilities&.elicitation
    unserved = unserved_elicitation_modes(elicitation)
    unless unserved.empty?
      raise ArgumentError, "initialize advertises elicitation modes no handler serves: #{unserved.join(', ')}"
    end

    @fs_capabilities = capabilities
    @terminal = terminal
    @elicitation_capabilities = elicitation
    result = @transport.request('initialize', request.to_h)
    response = parse(ACP::Types::InitializeResponse, result)
    return response if response.is_a?(ACP::RequestError)

    @mcp_advertised = agent_mcp_advertised?(result)
    return response if response.protocol_version == PROTOCOL_VERSION

    ACP::RequestError.unsupported_protocol_version(
      requested: request.protocol_version,
      returned: response.protocol_version
    )
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

  # @rbs request: ACP::Types::Unstable::ForkSessionRequest
  # @rbs return: (ACP::Types::Unstable::ForkSessionResponse | ACP::RequestError)
  def session_fork(request)
    parse(ACP::Types::Unstable::ForkSessionResponse, @transport.request('session/fork', request.to_h))
  end

  # @rbs request: ACP::Types::Unstable::ListProvidersRequest
  # @rbs return: (ACP::Types::Unstable::ListProvidersResponse | ACP::RequestError)
  def providers_list(request)
    parse(ACP::Types::Unstable::ListProvidersResponse, @transport.request('providers/list', request.to_h))
  end

  # @rbs request: ACP::Types::Unstable::SetProviderRequest
  # @rbs return: (ACP::Types::Unstable::SetProviderResponse | ACP::RequestError)
  def providers_set(request)
    parse(ACP::Types::Unstable::SetProviderResponse, @transport.request('providers/set', request.to_h))
  end

  # @rbs request: ACP::Types::Unstable::DisableProviderRequest
  # @rbs return: (ACP::Types::Unstable::DisableProviderResponse | ACP::RequestError)
  def providers_disable(request)
    parse(ACP::Types::Unstable::DisableProviderResponse, @transport.request('providers/disable', request.to_h))
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

  # Sends an extension request, keyed by its raw `_`-prefixed wire name, and
  # returns the agent's reply as-is: extension methods have no schema to
  # parse the result into.
  #
  # @rbs method: String
  # @rbs params: untyped
  # @rbs return: (Hash[String, untyped] | ACP::RequestError)
  def ext_request(method, params = nil)
    ACP::Extensions.validate_name(method)
    @transport.request(method, params)
  end

  # Always false off a handler thread.
  #
  # @rbs return: bool
  def cancelled?
    !!@transport.cancellation&.cancelled?
  end

  # @rbs method: String
  # @rbs params: untyped
  # @rbs return: void
  def ext_notify(method, params = nil)
    ACP::Extensions.validate_name(method)
    @transport.notify(method, params)
  end

  # Sends the provider's notification for an active mcp/message request.
  # Whether the agent supports the binding is the agent's own advertisement,
  # so this is not gated: a notification for a request the agent never sent
  # is dropped on its side.
  #
  # @rbs notification: ACP::Types::Unstable::MessageMcpNotification
  # @rbs return: void
  def mcp_message_notification(notification)
    @transport.notify('mcp/message', notification.to_h)
  end

  private

  # The route is only registered when a handler serves it, but the agent's
  # advertisement is only known after connect, so an unadvertised request
  # still reaches the route and is refused there.
  #
  # @rbs return: Hash[String, ACP::Transport::Stdio::_Handler]
  def mcp_requests
    return {} unless @mcp_message

    { 'mcp/message' => method(:mcp_message) }
  end

  # The stable McpCapabilities has no acp field, so the gate re-reads the raw
  # initialize reply with the unstable types when they are opted into.
  #
  # @rbs result: (Hash[String, untyped] | ACP::RequestError)
  # @rbs return: bool
  def agent_mcp_advertised?(result)
    return false unless defined?(ACP::Types::Unstable)
    return false unless result.is_a?(Hash)

    mcp = ACP::Types::Unstable::McpCapabilities.from_h(result['agentCapabilities']['mcpCapabilities'] || {})
    mcp.acp ? true : false
  rescue ACP::Types::ParseError, KeyError, TypeError, NoMethodError
    false
  end

  # @rbs type: ACP::AgentConnection::_Parser
  # @rbs result: (Hash[String, untyped] | ACP::RequestError)
  # @rbs return: untyped
  def parse(type, result)
    return result if result.is_a?(ACP::RequestError)

    type.from_h(result)
  rescue ACP::Types::ParseError, KeyError, TypeError, NoMethodError
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
  rescue ACP::Types::ParseError, KeyError, TypeError, NoMethodError => e
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
  rescue ACP::Types::ParseError => e
    ACP::RequestError.invalid_params([e.message])
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    replies = Thread::Queue.new
    register_permission(request.session_id, replies)
    # The handler runs on this connection's own thread, so the serving
    # identity must be carried over for cancelled? to see the cancel there.
    serving = @transport.cancellation
    Thread.new do
      ACP::Transport::Cancellation.current = serving
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
  rescue ACP::Types::ParseError => e
    ACP::RequestError.invalid_params([e.message])
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
  rescue ACP::Types::ParseError => e
    ACP::RequestError.invalid_params([e.message])
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    # Safe: connect refuses an advertised capability no handler serves.
    handler = @write_text_file #: ^(ACP::Types::WriteTextFileRequest) -> (ACP::Types::WriteTextFileResponse | ACP::RequestError)
    handler.call(request)
  end

  # The terminal routes are registered at start, before connect records the
  # advertised capability, so each one answers -32601 until then.
  #
  # @rbs params: untyped
  # @rbs return: (ACP::Types::CreateTerminalResponse | ACP::RequestError)
  def create_terminal(params)
    return ACP::RequestError.unadvertised('terminal') unless @terminal

    request = ACP::Types::CreateTerminalRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    # Safe: connect refuses an advertised capability no handler serves.
    handler = @create_terminal #: ^(ACP::Types::CreateTerminalRequest) -> (ACP::Types::CreateTerminalResponse | ACP::RequestError)
    handler.call(request)
  end

  # @rbs params: untyped
  # @rbs return: (ACP::Types::TerminalOutputResponse | ACP::RequestError)
  def terminal_output(params)
    return ACP::RequestError.unadvertised('terminal') unless @terminal

    request = ACP::Types::TerminalOutputRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    # Safe: connect refuses an advertised capability no handler serves.
    handler = @terminal_output #: ^(ACP::Types::TerminalOutputRequest) -> (ACP::Types::TerminalOutputResponse | ACP::RequestError)
    handler.call(request)
  end

  # The handler may block for as long as the command runs, so the transport
  # must serve each request on its own thread for this not to hold up others.
  #
  # @rbs params: untyped
  # @rbs return: (ACP::Types::WaitForTerminalExitResponse | ACP::RequestError)
  def wait_for_terminal_exit(params)
    return ACP::RequestError.unadvertised('terminal') unless @terminal

    request = ACP::Types::WaitForTerminalExitRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    # Safe: connect refuses an advertised capability no handler serves.
    handler = @wait_for_terminal_exit #: ^(ACP::Types::WaitForTerminalExitRequest) -> (ACP::Types::WaitForTerminalExitResponse | ACP::RequestError)
    handler.call(request)
  end

  # @rbs params: untyped
  # @rbs return: (ACP::Types::KillTerminalResponse | ACP::RequestError)
  def kill_terminal(params)
    return ACP::RequestError.unadvertised('terminal') unless @terminal

    request = ACP::Types::KillTerminalRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    # Safe: connect refuses an advertised capability no handler serves.
    handler = @kill_terminal #: ^(ACP::Types::KillTerminalRequest) -> (ACP::Types::KillTerminalResponse | ACP::RequestError)
    handler.call(request)
  end

  # @rbs params: untyped
  # @rbs return: (ACP::Types::ReleaseTerminalResponse | ACP::RequestError)
  def release_terminal(params)
    return ACP::RequestError.unadvertised('terminal') unless @terminal

    request = ACP::Types::ReleaseTerminalRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    # Safe: connect refuses an advertised capability no handler serves.
    handler = @release_terminal #: ^(ACP::Types::ReleaseTerminalRequest) -> (ACP::Types::ReleaseTerminalResponse | ACP::RequestError)
    handler.call(request)
  end

  # The route is registered at start, before connect records the agent's
  # advertisement, so an unadvertised request answers -32601 until then.
  #
  # @rbs params: untyped
  # @rbs return: (ACP::Types::Unstable::MessageMcpResponse::t | ACP::RequestError)
  def mcp_message(params)
    return ACP::RequestError.unadvertised_agent('mcpCapabilities.acp') unless @mcp_advertised

    request = ACP::Types::Unstable::MessageMcpRequest.from_h(params)
  rescue ACP::Types::ParseError => e
    ACP::RequestError.invalid_params([e.message])
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    # Safe: the route is only registered when a handler serves it.
    handler = @mcp_message #: ^(ACP::Types::Unstable::MessageMcpRequest) -> (ACP::Types::Unstable::MessageMcpResponse::t | ACP::RequestError)
    handler.call(request)
  end

  # The routes are registered at start, before connect records the advertised
  # capabilities, so a request for an unadvertised mode answers -32602.
  #
  # @rbs params: untyped
  # @rbs return: (ACP::Types::CreateElicitationResponse | ACP::RequestError)
  def create_elicitation(params)
    request = ACP::Types::CreateElicitationRequest.from_h(params)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_params
  else
    case request.mode
    when ACP::Types::CreateElicitationRequest::Mode::Form
      return ACP::RequestError.unadvertised_mode('elicitation.form') unless @elicitation_capabilities&.form
    when ACP::Types::CreateElicitationRequest::Mode::Url
      return ACP::RequestError.unadvertised_mode('elicitation.url') unless @elicitation_capabilities&.url

      register_elicitation(request.mode.elicitation_id)
    else
      return ACP::RequestError.unadvertised_mode("elicitation.#{request.mode['mode']}")
    end

    # Safe: connect refuses an advertised mode no handler serves.
    handler = @elicitation #: ^(ACP::Types::CreateElicitationRequest) -> (ACP::Types::CreateElicitationResponse | ACP::RequestError)
    handler.call(request)
  end

  # The spec requires a completion for an unknown or already-completed
  # elicitation id to be ignored, so only an id registered by a served
  # url-mode request reaches the handler. It runs on the transport's reader
  # thread, so it must return quickly.
  #
  # @rbs params: untyped
  # @rbs return: void
  def complete_elicitation(params)
    notification = ACP::Types::CompleteElicitationNotification.from_h(params)
  rescue KeyError, TypeError, NoMethodError => e
    @logger.warn("dropped malformed elicitation/complete: #{e.class}: #{e.message}")
  else
    known = @lock.synchronize { @outstanding_elicitations.delete(notification.elicitation_id) }
    @complete_elicitation&.call(notification) if known
  end

  # @rbs elicitation_id: String
  # @rbs return: void
  def register_elicitation(elicitation_id)
    @lock.synchronize { @outstanding_elicitations[elicitation_id] = true }
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

  # The terminal capabilities initialize advertises that no injected handler
  # serves.
  #
  # @rbs capabilities: bool?
  # @rbs return: Array[String]
  def unserved_terminal_methods(capabilities)
    {
      'terminal.create' => capabilities && !@create_terminal,
      'terminal.output' => capabilities && !@terminal_output,
      'terminal.wait_for_exit' => capabilities && !@wait_for_terminal_exit,
      'terminal.kill' => capabilities && !@kill_terminal,
      'terminal.release' => capabilities && !@release_terminal
    }.select { |_, unserved| unserved }.keys
  end

  # The elicitation capabilities initialize advertises that no injected
  # handler serves.
  #
  # @rbs capabilities: ACP::Types::ElicitationCapabilities?
  # @rbs return: Array[String]
  def unserved_elicitation_modes(capabilities)
    {
      'elicitation.form' => capabilities&.form && !@elicitation,
      'elicitation.url' => capabilities&.url && !@elicitation
    }.select { |_, unserved| unserved }.keys
  end
end
