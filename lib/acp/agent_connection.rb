# frozen_string_literal: true

class ACP::AgentConnection
  # @rbs @transport: ACP::AgentConnection::_Transport
  # @rbs @initialize_response: ACP::Types::InitializeResponse
  # @rbs @factory: ^(ACP::AgentConnection::Client) -> ACP::AgentConnection::_Agent

  PROTOCOL_VERSION = 1 #: Integer
  INVALID_PARAMS = ACP::Transport::ResponseError.new(code: -32_602, message: 'Invalid params') #: ACP::Transport::ResponseError
  OPTIONAL = [
    ACP::AgentConnection::OptionalMethod::LoadSession,
    ACP::AgentConnection::OptionalMethod::ListSessions,
    ACP::AgentConnection::OptionalMethod::Authenticate,
    ACP::AgentConnection::OptionalMethod::ResumeSession,
    ACP::AgentConnection::OptionalMethod::CloseSession,
    ACP::AgentConnection::OptionalMethod::DeleteSession
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
  # @rbs &factory: (ACP::AgentConnection::Client) -> ACP::AgentConnection::_Agent
  # @rbs return: void
  def initialize(transport:, capabilities:, agent_info: nil, auth_methods: [], &factory)
    @transport = transport
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
  # @rbs return: Hash[String, ^(untyped) -> (ACP::Transport::Result | ACP::Transport::Reply)]
  def requests(agent, client)
    # Safe: start drops the optional handlers initialize does not advertise
    # or the agent does not define, and checks the agent defines the rest.
    full = agent #: ACP::AgentConnection::_FullAgent
    {
      'initialize' => route(ACP::Types::InitializeRequest) { |request| connect(client, request) },
      'authenticate' => route(ACP::Types::AuthenticateRequest) { |request| respond(full.authenticate(request)) },
      'session/new' => route(ACP::Types::NewSessionRequest) { |request| new_session(agent, request) },
      'session/prompt' => route(ACP::Types::PromptRequest) { |request| respond(agent.prompt(request)) },
      'session/load' => route(ACP::Types::LoadSessionRequest) { |request| respond(full.load_session(request)) },
      'session/list' => route(ACP::Types::ListSessionsRequest) { |request| respond(full.list_sessions(request)) },
      'session/resume' => route(ACP::Types::ResumeSessionRequest) { |request| respond(full.resume_session(request)) },
      'session/close' => route(ACP::Types::CloseSessionRequest) { |request| respond(full.close_session(request)) },
      'session/delete' => route(ACP::Types::DeleteSessionRequest) { |request| respond(full.delete_session(request)) },
      'session/set_mode' => route(ACP::Types::SetSessionModeRequest) do |request|
        respond(full.change_session_mode(request))
      end,
      'session/set_config_option' => route(ACP::Types::SetSessionConfigOptionRequest) do |request|
        respond(full.change_session_config_option(request))
      end
    }
  end

  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs return: Hash[String, ^(untyped) -> void]
  def notifications(agent)
    { 'session/cancel' => ->(params) { agent.cancel(ACP::Types::CancelNotification.from_h(params)) } }
  end

  # Generated from_h raises on a missing key or a value of the wrong shape.
  #
  # @rbs type: ACP::AgentConnection::_Parser
  # @rbs &handle: (untyped) -> (ACP::Transport::Result | ACP::Transport::Reply)
  # @rbs return: ^(untyped) -> (ACP::Transport::Result | ACP::Transport::Reply)
  def route(type, &)
    lambda do |params|
      request = type.from_h(params)
    rescue KeyError, TypeError, NoMethodError
      ACP::Transport::Result.error(INVALID_PARAMS)
    else
      yield(request)
    end
  end

  # @rbs response: ACP::AgentConnection::_Response | ACP::Transport::ResponseError
  # @rbs return: ACP::Transport::Result
  def respond(response)
    case response
    when ACP::Transport::ResponseError then ACP::Transport::Result.error(response)
    else ACP::Transport::Result.ok(response.to_h)
    end
  end

  # @rbs client: ACP::AgentConnection::Client
  # @rbs request: ACP::Types::InitializeRequest
  # @rbs return: ACP::Transport::Result
  def connect(client, request)
    client.capabilities = request.client_capabilities || ACP::Types::ClientCapabilities.new
    respond(@initialize_response)
  end

  # session_created runs after the reply because the client must know the
  # session id before updates for it (e.g. available commands) arrive.
  #
  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs request: ACP::Types::NewSessionRequest
  # @rbs return: ACP::Transport::Result | ACP::Transport::Reply
  def new_session(agent, request)
    response = agent.new_session(request)
    result = respond(response)
    return result unless response.is_a?(ACP::Types::NewSessionResponse) && agent.respond_to?(:session_created)

    hook = agent #: ACP::AgentConnection::_Agent & ACP::AgentConnection::_SessionCreated
    ACP::Transport::Reply.new(result, after: -> { hook.session_created(response) })
  end
end
