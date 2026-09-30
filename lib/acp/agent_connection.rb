# frozen_string_literal: true

class ACP::AgentConnection
  # @rbs @transport: ACP::AgentConnection::_Transport
  # @rbs @capabilities: ACP::Types::AgentCapabilities
  # @rbs @agent_info: ACP::Types::Implementation?
  # @rbs @auth_methods: Array[ACP::Types::AuthMethod::t]
  # @rbs @factory: ^(ACP::AgentConnection::Client) -> ACP::AgentConnection::_Agent

  PROTOCOL_VERSION = 1 #: Integer
  INVALID_PARAMS = ACP::Transport::ResponseError.new(code: -32_602, message: 'Invalid params') #: ACP::Transport::ResponseError
  OPTIONAL = { 'session/load' => :load_session, 'session/list' => :list_sessions }.freeze #: Hash[String, Symbol]

  # @rbs transport: ACP::AgentConnection::_Transport
  # @rbs capabilities: ACP::Types::AgentCapabilities
  # @rbs agent_info: ACP::Types::Implementation?
  # @rbs auth_methods: Array[ACP::Types::AuthMethod::t]
  # @rbs &factory: (ACP::AgentConnection::Client) -> ACP::AgentConnection::_Agent
  # @rbs return: void
  def initialize(transport:, capabilities:, agent_info: nil, auth_methods: [], &factory)
    @transport = transport
    @capabilities = capabilities
    @agent_info = agent_info
    @auth_methods = auth_methods
    @factory = factory
  end

  # @rbs return: Thread
  def start
    client = ACP::AgentConnection::Client.new(peer: @transport)
    agent = @factory.call(client)
    unrouted = unadvertised
    missing = OPTIONAL.except(*unrouted).values.reject { |name| agent.respond_to?(name) }
    raise ArgumentError, "capabilities advertise methods the agent lacks: #{missing.join(', ')}" unless missing.empty?

    @transport.start(requests: requests(agent, client).except(*unrouted), notifications: notifications(agent))
  end

  private

  # @rbs return: Array[String]
  def unadvertised
    {
      'session/load' => @capabilities.load_session,
      'session/list' => @capabilities.session_capabilities&.list
    }.reject { |_, capability| capability }.keys
  end

  # @rbs agent: ACP::AgentConnection::_Agent
  # @rbs client: ACP::AgentConnection::Client
  # @rbs return: Hash[String, ^(untyped) -> (ACP::Transport::Result | ACP::Transport::Reply)]
  def requests(agent, client)
    # Safe: start drops the load/list handlers the capabilities do not
    # advertise and checks the agent defines the rest.
    full = agent #: ACP::AgentConnection::_Agent & ACP::AgentConnection::_LoadSession & ACP::AgentConnection::_ListSessions
    {
      'initialize' => route(ACP::Types::InitializeRequest) { |request| connect(client, request) },
      'session/new' => route(ACP::Types::NewSessionRequest) { |request| new_session(agent, request) },
      'session/prompt' => route(ACP::Types::PromptRequest) { |request| respond(agent.prompt(request)) },
      'session/load' => route(ACP::Types::LoadSessionRequest) { |request| respond(full.load_session(request)) },
      'session/list' => route(ACP::Types::ListSessionsRequest) { |request| respond(full.list_sessions(request)) }
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
    respond(
      ACP::Types::InitializeResponse.new(
        protocol_version: PROTOCOL_VERSION,
        agent_capabilities: @capabilities,
        auth_methods: @auth_methods,
        agent_info: @agent_info
      )
    )
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
