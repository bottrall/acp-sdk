# frozen_string_literal: true

class ACP::ClientConnection
  # @rbs @transport: ACP::Transport::Stdio
  # @rbs @streams: ACP::ClientConnection::Streams
  # @rbs @inbound: ACP::ClientConnection::Inbound

  IGNORE = ->(_notification) {} #: ^(ACP::Types::SessionNotification) -> void

  # Wires a connection from its handlers. The fs, terminal and elicitation
  # handlers are objects grouped by capability; each needs only the methods of
  # the capabilities initialize advertises.
  #
  # @rbs transport: ACP::Transport::Stdio
  # @rbs permission: ACP::ClientConnection::_PermissionHandler
  # @rbs updates: ACP::ClientConnection::_UpdateHandler
  # @rbs fs: ACP::ClientConnection::_FileSystem?
  # @rbs terminal: ACP::ClientConnection::_Terminal?
  # @rbs elicitation: ACP::ClientConnection::_Elicitation?
  # @rbs mcp_message: (^(ACP::Types::Unstable::MessageMcpRequest) ->
  #   (ACP::Types::Unstable::MessageMcpResponse::t | ACP::RequestError))?
  # @rbs extension_requests: Hash[String, ^(untyped) -> untyped]
  # @rbs extension_notifications: Hash[String, ^(untyped) -> void]
  # @rbs logger: ACP::Transport::_Logger
  # @rbs return: ACP::ClientConnection
  def self.build(
    transport:,
    permission:,
    updates: IGNORE,
    fs: nil, # rubocop:disable Naming/MethodParameterName -- named after ClientCapabilities#fs
    terminal: nil,
    elicitation: nil,
    mcp_message: nil,
    extension_requests: {},
    extension_notifications: {},
    logger: ACP::Transport::StderrLogger.new
  )
    inbound = Inbound.new(
      elicitations: Elicitations.new(handler: elicitation, logger:),
      fs:,
      terminal:,
      elicitation:,
      mcp_message:,
      extension_requests:,
      extension_notifications:
    )
    new(transport:, streams: Streams.new(sender: transport, permission:, updates:, logger:), inbound:)
  end

  # @rbs transport: ACP::Transport::Stdio
  # @rbs streams: ACP::ClientConnection::Streams
  # @rbs inbound: ACP::ClientConnection::Inbound
  # @rbs return: void
  def initialize(transport:, streams:, inbound:)
    @transport = transport
    @streams = streams
    @inbound = inbound
  end

  # @rbs return: Thread
  def start
    @transport.start(
      requests: { 'session/request_permission' => @streams.method(:request_permission), **@inbound.requests },
      notifications: { 'session/update' => @streams.method(:dispatch), **@inbound.notifications }
    )
  end

  # Ruby reserves initialize for the constructor, so the initialize request is
  # sent by connect.
  #
  # @rbs request: ACP::Types::InitializeRequest
  # @rbs return: ACP::Types::InitializeResponse | ACP::RequestError
  def connect(request)
    @inbound.advertise(request.client_capabilities)
    result = @transport.request('initialize', request.to_h)
    response = parse(ACP::Types::InitializeResponse, result)
    return response if response.is_a?(ACP::RequestError)

    # Safe: parse only calls from_h on a Hash, and its RequestError answer
    # short-circuited above.
    reply = result #: Hash[String, untyped]
    @inbound.mcp_advertised = ACP::Protocol.mcp_acp_advertised?(reply['agentCapabilities'] || {})
    return response if response.protocol_version == ACP::Protocol::PROTOCOL_VERSION

    ACP::RequestError.unsupported_protocol_version(
      requested: request.protocol_version,
      returned: response.protocol_version
    )
  end

  # @rbs request: ACP::Types::NewSessionRequest
  # @rbs return: ACP::Types::NewSessionResponse | ACP::RequestError
  def new_session(request)
    parse(ACP::Types::NewSessionResponse, @transport.request('session/new', request.to_h))
  end

  # @rbs request: ACP::Types::PromptRequest
  # @rbs &block: (ACP::Types::SessionUpdate::t) -> void
  # @rbs return: ACP::Types::PromptResponse | ACP::RequestError
  def prompt_session(request, &)
    parse(ACP::Types::PromptResponse, @streams.stream(request.session_id, 'session/prompt', request.to_h, &))
  end

  # @rbs request: ACP::Types::LoadSessionRequest
  # @rbs &block: (ACP::Types::SessionUpdate::t) -> void
  # @rbs return: ACP::Types::LoadSessionResponse | ACP::RequestError
  def load_session(request, &)
    parse(ACP::Types::LoadSessionResponse, @streams.stream(request.session_id, 'session/load', request.to_h, &))
  end

  # @rbs request: ACP::Types::ListSessionsRequest
  # @rbs return: ACP::Types::ListSessionsResponse | ACP::RequestError
  def list_sessions(request)
    parse(ACP::Types::ListSessionsResponse, @transport.request('session/list', request.to_h))
  end

  # The agent does not replay history on resume, so unlike load_session there
  # is nothing to stream and no block is taken.
  #
  # @rbs request: ACP::Types::ResumeSessionRequest
  # @rbs return: ACP::Types::ResumeSessionResponse | ACP::RequestError
  def resume_session(request)
    parse(ACP::Types::ResumeSessionResponse, @transport.request('session/resume', request.to_h))
  end

  # @rbs request: ACP::Types::CloseSessionRequest
  # @rbs return: ACP::Types::CloseSessionResponse | ACP::RequestError
  def close_session(request)
    parse(ACP::Types::CloseSessionResponse, @transport.request('session/close', request.to_h))
  end

  # @rbs request: ACP::Types::DeleteSessionRequest
  # @rbs return: ACP::Types::DeleteSessionResponse | ACP::RequestError
  def delete_session(request)
    parse(ACP::Types::DeleteSessionResponse, @transport.request('session/delete', request.to_h))
  end

  # @rbs request: ACP::Types::Unstable::ForkSessionRequest
  # @rbs return: (ACP::Types::Unstable::ForkSessionResponse | ACP::RequestError)
  def fork_session(request)
    parse(ACP::Types::Unstable::ForkSessionResponse, @transport.request('session/fork', request.to_h))
  end

  # @rbs request: ACP::Types::Unstable::ListProvidersRequest
  # @rbs return: (ACP::Types::Unstable::ListProvidersResponse | ACP::RequestError)
  def list_providers(request)
    parse(ACP::Types::Unstable::ListProvidersResponse, @transport.request('providers/list', request.to_h))
  end

  # @rbs request: ACP::Types::Unstable::SetProviderRequest
  # @rbs return: (ACP::Types::Unstable::SetProviderResponse | ACP::RequestError)
  # The name is the wire-mandated providers/set, not an attribute writer.
  def set_provider(request) # rubocop:disable Naming/AccessorMethodName
    parse(ACP::Types::Unstable::SetProviderResponse, @transport.request('providers/set', request.to_h))
  end

  # @rbs request: ACP::Types::Unstable::DisableProviderRequest
  # @rbs return: (ACP::Types::Unstable::DisableProviderResponse | ACP::RequestError)
  def disable_provider(request)
    parse(ACP::Types::Unstable::DisableProviderResponse, @transport.request('providers/disable', request.to_h))
  end

  # The spec requires a pending session/request_permission to be answered with
  # the cancelled outcome once the turn is cancelled. The notification goes
  # first so the wire order is cancel, then the cancelled replies.
  #
  # @rbs notification: ACP::Types::CancelNotification
  # @rbs return: void
  def cancel_session(notification)
    @transport.notify('session/cancel', notification.to_h)
    @streams.cancel(notification.session_id)
  end

  # @rbs request: ACP::Types::SetSessionModeRequest
  # @rbs return: ACP::Types::SetSessionModeResponse | ACP::RequestError
  # The name is the wire-mandated session/set_mode, not an attribute writer.
  def set_session_mode(request) # rubocop:disable Naming/AccessorMethodName
    parse(ACP::Types::SetSessionModeResponse, @transport.request('session/set_mode', request.to_h))
  end

  # The reply carries the session's complete option list, so it replaces any
  # state held from an earlier reply rather than merging into it.
  #
  # @rbs request: ACP::Types::SetSessionConfigOptionRequest
  # @rbs return: ACP::Types::SetSessionConfigOptionResponse | ACP::RequestError
  # The name is the wire-mandated session/set_config_option, not an attribute writer.
  def set_session_config_option(request) # rubocop:disable Naming/AccessorMethodName
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

  # Extension methods have no schema to parse the result into.
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

  # Unlike the mcp/message serve route, this send is not gated: a notification
  # has no reply to carry a refusal, and the agent drops what it did not
  # advertise.
  #
  # @rbs notification: ACP::Types::Unstable::MessageMcpNotification
  # @rbs return: void
  def mcp_message_notification(notification)
    @transport.notify('mcp/message', notification.to_h)
  end

  private

  # @rbs type: ACP::Transport::_Parser
  # @rbs result: (Hash[String, untyped] | ACP::RequestError)
  # @rbs return: untyped
  def parse(type, result)
    return result if result.is_a?(ACP::RequestError)

    response = ACP::Types.parse(type, result)
    response.is_a?(ACP::Types::ParseError) ? ACP::RequestError.invalid_response(result) : response
  end
end
