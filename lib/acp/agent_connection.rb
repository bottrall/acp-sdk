# frozen_string_literal: true

class ACP::AgentConnection
  # @rbs @transport: ACP::AgentConnection::_Transport
  # @rbs @initialize_response: ACP::Types::InitializeResponse
  # @rbs @factory: ^(ACP::AgentConnection::Client) -> ACP::AgentConnection::_Agent
  # @rbs @logger: ACP::Transport::_Logger

  PROTOCOL_VERSION = 1 #: Integer
  OPTIONAL = [
    ACP::AgentConnection::OptionalMethod::LoadSession,
    ACP::AgentConnection::OptionalMethod::ListSessions,
    ACP::AgentConnection::OptionalMethod::Authenticate,
    ACP::AgentConnection::OptionalMethod::ResumeSession,
    ACP::AgentConnection::OptionalMethod::CloseSession,
    ACP::AgentConnection::OptionalMethod::DeleteSession,
    ACP::AgentConnection::OptionalMethod::Logout
  ].freeze #: Array[ACP::AgentConnection::_OptionalMethod]
  # The schema has no initialize capability for modes or config options: an
  # agent offers them per session, in its session responses, so they are
  # routed whenever the agent defines them.
  PER_SESSION = {
    'session/set_mode' => :change_session_mode,
    'session/set_config_option' => :change_session_config_option
  }.freeze #: Hash[String, Symbol]

  # @rbs transport: ACP::AgentConnection::_Transport
  # @rbs capabilities: ACP::Types::AgentCapabilities
  # @rbs agent_info: ACP::Types::Implementation?
  # @rbs auth_methods: Array[ACP::Types::AuthMethod::t]
  # @rbs logger: ACP::Transport::_Logger
  # @rbs &factory: (ACP::AgentConnection::Client) -> ACP::AgentConnection::_Agent
  # @rbs return: void
  def initialize(
    transport:,
    capabilities:,
    agent_info: nil,
    auth_methods: [],
    logger: ACP::Transport::StderrLogger.new,
    &factory
  )
    @transport = transport
    @logger = logger
    @initialize_response = ACP::Types::InitializeResponse.new(
      protocol_version: PROTOCOL_VERSION,
      agent_capabilities: capabilities,
      auth_methods:,
      agent_info:
    )
    @factory = factory
  end

  # @rbs return: Thread
  def start
    client = ACP::AgentConnection::Client.new(peer: @transport)
    agent = @factory.call(client)
    advertised, unadvertised = OPTIONAL.partition { |method| method.advertised?(@initialize_response) }
    missing = advertised.map(&:agent_method).reject { |name| agent.respond_to?(name) }
    raise ArgumentError, "initialize advertises methods the agent lacks: #{missing.join(', ')}" unless missing.empty?

    unrouted = unadvertised.map(&:rpc_method) + PER_SESSION.reject { |_, name| agent.respond_to?(name) }.keys
    @transport.start(requests: requests(agent, client).except(*unrouted), notifications: notifications(agent))
  end

  private

  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs client: ACP::AgentConnection::Client
  # @rbs return: Hash[String, ^(untyped) -> (ACP::AgentConnection::_Response | ACP::RequestError | ACP::Transport::Reply)]
  def requests(agent, client)
    # Safe: start drops the optional handlers initialize does not advertise
    # or the agent does not define, and checks the agent defines the rest.
    full = agent #: ACP::AgentConnection::_FullAgent
    {
      'initialize' => route(ACP::Types::InitializeRequest) { |request| connect(client, request) },
      'authenticate' => route(ACP::Types::AuthenticateRequest) { |request| full.authenticate(request) },
      'session/new' => route(ACP::Types::NewSessionRequest) { |request| new_session(agent, request) },
      'session/prompt' => route(ACP::Types::PromptRequest) { |request| agent.prompt(request) },
      'session/load' => route(ACP::Types::LoadSessionRequest) { |request| full.load_session(request) },
      'session/list' => route(ACP::Types::ListSessionsRequest) { |request| full.list_sessions(request) },
      'session/resume' => route(ACP::Types::ResumeSessionRequest) { |request| full.resume_session(request) },
      'session/close' => route(ACP::Types::CloseSessionRequest) { |request| full.close_session(request) },
      'session/delete' => route(ACP::Types::DeleteSessionRequest) { |request| full.delete_session(request) },
      'logout' => route(ACP::Types::LogoutRequest) { |request| full.logout(request) },
      'session/set_mode' => route(ACP::Types::SetSessionModeRequest) { |request| full.change_session_mode(request) },
      'session/set_config_option' => route(ACP::Types::SetSessionConfigOptionRequest) do |request|
        full.change_session_config_option(request)
      end
    }
  end

  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs return: Hash[String, ^(untyped) -> void]
  def notifications(agent)
    { 'session/cancel' => ->(params) { cancel(agent, params) } }
  end

  # A notification has no reply to carry a parse failure.
  #
  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs params: untyped
  # @rbs return: void
  def cancel(agent, params)
    notification = ACP::Types::CancelNotification.from_h(params)
  rescue KeyError, TypeError, NoMethodError => e
    @logger.warn("dropped malformed session/cancel: #{e.class}: #{e.message}")
  else
    agent.cancel(notification)
  end

  # Generated from_h raises on a missing key or a value of the wrong shape.
  #
  # @rbs type: ACP::AgentConnection::_Parser
  # @rbs &handle: (untyped) -> (ACP::AgentConnection::_Response | ACP::RequestError | ACP::Transport::Reply)
  # @rbs return: ^(untyped) -> (ACP::AgentConnection::_Response | ACP::RequestError | ACP::Transport::Reply)
  def route(type, &)
    lambda do |params|
      request = type.from_h(params)
    rescue KeyError, TypeError, NoMethodError
      ACP::RequestError.invalid_params
    else
      yield(request)
    end
  end

  # @rbs client: ACP::AgentConnection::Client
  # @rbs request: ACP::Types::InitializeRequest
  # @rbs return: ACP::Types::InitializeResponse
  def connect(client, request)
    client.capabilities = request.client_capabilities || ACP::Types::ClientCapabilities.new
    @initialize_response
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
