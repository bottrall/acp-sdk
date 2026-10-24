# frozen_string_literal: true

class ACP::AgentConnection
  # @rbs @transport: ACP::Transport::Stdio
  # @rbs @capabilities: ACP::Types::AgentCapabilities
  # @rbs @agent_info: ACP::Types::Implementation?
  # @rbs @auth_methods: Array[ACP::Types::AuthMethod::t]
  # @rbs @factory: ^(ACP::AgentConnection::Client) -> ACP::AgentConnection::_Agent
  # @rbs @extension_requests: Hash[String, ^(untyped) -> untyped]
  # @rbs @extension_notifications: Hash[String, ^(untyped) -> void]
  # @rbs @logger: ACP::Transport::_Logger

  OPTIONAL_ROUTES = [
    OptionalRoute.new(
      rpc_method: 'authenticate',
      type: ACP::Types::AuthenticateRequest,
      agent_method: :authenticate,
      path: %i[auth_methods any?]
    ) { |agent, request| agent.authenticate(request) },
    OptionalRoute.new(
      rpc_method: 'session/load',
      type: ACP::Types::LoadSessionRequest,
      agent_method: :load_session,
      path: %i[agent_capabilities load_session]
    ) { |agent, request| agent.load_session(request) },
    OptionalRoute.new(
      rpc_method: 'session/list',
      type: ACP::Types::ListSessionsRequest,
      agent_method: :list_sessions,
      path: %i[agent_capabilities session_capabilities list]
    ) { |agent, request| agent.list_sessions(request) },
    OptionalRoute.new(
      rpc_method: 'session/resume',
      type: ACP::Types::ResumeSessionRequest,
      agent_method: :resume_session,
      path: %i[agent_capabilities session_capabilities resume]
    ) { |agent, request| agent.resume_session(request) },
    OptionalRoute.new(
      rpc_method: 'session/close',
      type: ACP::Types::CloseSessionRequest,
      agent_method: :close_session,
      path: %i[agent_capabilities session_capabilities close]
    ) { |agent, request| agent.close_session(request) },
    OptionalRoute.new(
      rpc_method: 'session/delete',
      type: ACP::Types::DeleteSessionRequest,
      agent_method: :delete_session,
      path: %i[agent_capabilities session_capabilities delete]
    ) { |agent, request| agent.delete_session(request) },
    OptionalRoute.new(
      rpc_method: 'logout',
      type: ACP::Types::LogoutRequest,
      agent_method: :logout,
      path: %i[agent_capabilities auth logout]
    ) { |agent, request| agent.logout(request) },
    OptionalRoute.new(
      rpc_method: 'session/set_mode',
      type: ACP::Types::SetSessionModeRequest,
      agent_method: :change_session_mode,
      path: nil
    ) { |agent, request| agent.change_session_mode(request) },
    OptionalRoute.new(
      rpc_method: 'session/set_config_option',
      type: ACP::Types::SetSessionConfigOptionRequest,
      agent_method: :change_session_config_option,
      path: nil
    ) { |agent, request| agent.change_session_config_option(request) }
  ].freeze #: Array[ACP::AgentConnection::OptionalRoute]

  # @rbs transport: ACP::Transport::Stdio
  # @rbs capabilities: ACP::Types::AgentCapabilities
  # @rbs agent_info: ACP::Types::Implementation?
  # @rbs auth_methods: Array[ACP::Types::AuthMethod::t]
  # @rbs extension_requests: Hash[String, ^(untyped) -> untyped]
  # @rbs extension_notifications: Hash[String, ^(untyped) -> void]
  # @rbs logger: ACP::Transport::_Logger
  # @rbs &factory: (ACP::AgentConnection::Client) -> ACP::AgentConnection::_Agent
  # @rbs return: void
  def initialize(
    transport:,
    capabilities:,
    agent_info: nil,
    auth_methods: [],
    extension_requests: {},
    extension_notifications: {},
    logger: ACP::Transport::StderrLogger.new,
    &factory
  )
    @transport = transport
    @logger = logger
    @capabilities = capabilities
    @agent_info = agent_info
    @auth_methods = auth_methods
    @extension_requests = extension_requests
    @extension_notifications = extension_notifications
    ACP::Extensions.validate_names(extension_requests.keys + extension_notifications.keys)
    @factory = factory
  end

  # @rbs return: Thread
  def start
    client = ACP::AgentConnection::Client.new(peer: @transport, mcp_advertised: mcp_acp_advertised?)
    agent = @factory.call(client)
    routes = OPTIONAL_ROUTES + unstable_routes
    # Routes are fixed before a client connects, so the check sees the
    # unfiltered auth methods: a terminal-capable client still needs
    # authenticate routed.
    response = initialize_response(@auth_methods)
    missing = routes.select { |route| route.advertised?(response) && !agent.respond_to?(route.agent_method) }
    unless missing.empty?
      raise ArgumentError, "initialize advertises methods the agent lacks: #{missing.map(&:agent_method).join(', ')}"
    end

    if mcp_acp_advertised? && !agent.respond_to?(:mcp_message_notification)
      raise ArgumentError, 'initialize advertises mcpCapabilities.acp but the agent lacks mcp_message_notification'
    end

    routed = routes.select { |route| route.routed?(response, agent) }
    @transport.start(
      requests: requests(agent, client, routed).merge(@extension_requests),
      notifications: notifications(agent).merge(@extension_notifications)
    )
  end

  private

  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs client: ACP::AgentConnection::Client
  # @rbs optional: Array[ACP::AgentConnection::OptionalRoute]
  # @rbs return: Hash[String, ^(untyped) -> (ACP::Transport::_Response | ACP::RequestError | ACP::Transport::Reply)]
  def requests(agent, client, optional)
    # Safe: start passes only the optional routes the agent defines.
    full = agent #: ACP::AgentConnection::_FullAgent
    optional_requests = optional.to_h do |entry|
      [entry.rpc_method, route(entry.type) { |request| entry.handle.call(full, request) }]
    end
    {
      'initialize' => route(ACP::Types::InitializeRequest) { |request| connect(client, request) },
      'session/new' => route(ACP::Types::NewSessionRequest) { |request| new_session(agent, request) },
      'session/prompt' => route(ACP::Types::PromptRequest) { |request| agent.prompt(request) }
    }.merge(optional_requests)
  end

  # @rbs return: Array[ACP::AgentConnection::OptionalRoute]
  def unstable_routes
    # The rows reference the unstable request types, so without the guard start
    # would raise NameError even for an agent that never advertises fork or
    # providers.
    return [] unless ACP::Types.unstable_enabled?

    [
      OptionalRoute.new(
        rpc_method: 'session/fork',
        type: ACP::Types::Unstable::ForkSessionRequest,
        agent_method: :fork_session,
        path: %i[agent_capabilities session_capabilities fork]
      ) { |agent, request| agent.fork_session(request) },
      OptionalRoute.new(
        rpc_method: 'providers/list',
        type: ACP::Types::Unstable::ListProvidersRequest,
        agent_method: :list_providers,
        path: %i[agent_capabilities providers]
      ) { |agent, request| agent.list_providers(request) },
      OptionalRoute.new(
        rpc_method: 'providers/set',
        type: ACP::Types::Unstable::SetProviderRequest,
        agent_method: :set_provider,
        path: %i[agent_capabilities providers]
      ) { |agent, request| agent.set_provider(request) },
      OptionalRoute.new(
        rpc_method: 'providers/disable',
        type: ACP::Types::Unstable::DisableProviderRequest,
        agent_method: :disable_provider,
        path: %i[agent_capabilities providers]
      ) { |agent, request| agent.disable_provider(request) }
    ]
  end

  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs return: Hash[String, ^(untyped) -> void]
  def notifications(agent)
    routes = { 'session/cancel' => ->(params) { cancel(agent, params) } }
    return routes unless mcp_acp_advertised?

    routes.merge('mcp/message' => ->(params) { mcp_message_notification(agent, params) })
  end

  # A notification has no reply to carry a parse failure.
  #
  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs params: untyped
  # @rbs return: void
  def cancel(agent, params)
    notification = ACP::Types.parse(ACP::Types::CancelNotification, params)
    if notification.is_a?(ACP::Types::ParseError)
      @logger.warn("dropped malformed session/cancel: #{notification.message}")
    else
      agent.cancel(notification)
    end
  end

  # @rbs return: bool
  def mcp_acp_advertised?
    ACP::Protocol.mcp_acp_advertised?(@capabilities)
  end

  # A notification has no reply to carry a parse failure.
  #
  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs params: untyped
  # @rbs return: void
  def mcp_message_notification(agent, params)
    notification = ACP::Types.parse(ACP::Types::Unstable::MessageMcpNotification, params)
    if notification.is_a?(ACP::Types::ParseError)
      @logger.warn("dropped malformed mcp/message: #{notification.message}")
    else
      hook = agent #: ACP::AgentConnection::_Agent & ACP::AgentConnection::_McpMessageNotification
      hook.mcp_message_notification(notification)
    end
  end

  # @rbs type: ACP::Transport::_Parser
  # @rbs &handle: (untyped) -> (ACP::Transport::_Response | ACP::RequestError | ACP::Transport::Reply)
  # @rbs return: ^(untyped) -> (ACP::Transport::_Response | ACP::RequestError | ACP::Transport::Reply)
  def route(type, &)
    lambda do |params|
      request = ACP::Types.parse(type, params)
      next ACP::RequestError.invalid_params([request.message]) if request.is_a?(ACP::Types::ParseError)

      yield(request)
    end
  end

  # @rbs client: ACP::AgentConnection::Client
  # @rbs request: ACP::Types::InitializeRequest
  # @rbs return: ACP::Types::InitializeResponse
  def connect(client, request)
    capabilities = request.client_capabilities || ACP::Types::ClientCapabilities.new
    client.capabilities = capabilities
    initialize_response(auth_methods(capabilities))
  end

  # @rbs auth_methods: Array[ACP::Types::AuthMethod::t]
  # @rbs return: ACP::Types::InitializeResponse
  def initialize_response(auth_methods)
    ACP::Types::InitializeResponse.new(
      protocol_version: ACP::Protocol::PROTOCOL_VERSION,
      agent_capabilities: @capabilities,
      auth_methods:,
      agent_info: @agent_info
    )
  end

  # @rbs capabilities: ACP::Types::ClientCapabilities
  # @rbs return: Array[ACP::Types::AuthMethod::t]
  def auth_methods(capabilities)
    return @auth_methods if capabilities.auth&.terminal

    @auth_methods.reject { |method| terminal_auth_method?(method) }
  end

  # @rbs method: ACP::Types::AuthMethod::t
  # @rbs return: bool
  def terminal_auth_method?(method)
    method.is_a?(ACP::Types::AuthMethod::Terminal) || (method.is_a?(Hash) && method['type'] == 'terminal')
  end

  # session_created runs after the reply because the client must know the
  # session id before updates for it (e.g. available commands) arrive.
  #
  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs request: ACP::Types::NewSessionRequest
  # @rbs return: (ACP::Types::NewSessionResponse | ACP::RequestError | ACP::Transport::Reply)
  def new_session(agent, request)
    response = agent.new_session(request)
    return response unless response.is_a?(ACP::Types::NewSessionResponse) && agent.respond_to?(:session_created)

    hook = agent #: ACP::AgentConnection::_Agent & ACP::AgentConnection::_SessionCreated
    ACP::Transport::Reply.new(response, after: -> { hook.session_created(response) })
  end
end
