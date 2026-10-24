# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'open3'

require 'acp/types/unstable'

class AgentConnectionAgent
  REQUIRED = %i[new_session prompt cancel].freeze

  attr_reader :calls

  def initialize(*optional, replies: {})
    @calls = []
    (REQUIRED + optional).each do |name|
      define_singleton_method(name) do |argument|
        @calls << [name, argument]
        replies.fetch(name, name)
      end
    end
  end
end

class AgentConnectionTransport
  attr_reader :requests, :notifications, :sent

  def initialize(reader)
    @reader = reader
    @sent = []
  end

  def start(requests:, notifications:)
    @requests = requests
    @notifications = notifications
    @reader
  end

  def request(method, params = nil)
    @sent << [:request, method, params]
    {}
  end

  def notify(method, params = nil)
    @sent << [:notify, method, params]
  end
end

describe ACP::AgentConnection do
  optional = %i[
    authenticate
    load_session
    list_sessions
    resume_session
    close_session
    delete_session
    logout
    fork_session
    list_providers
    set_provider
    disable_provider
  ].freeze
  per_session = %i[change_session_mode change_session_config_option].freeze
  set_provider = { 'providerId' => 'anthropic', 'apiType' => 'anthropic', 'baseUrl' => 'https://api.example.com' }
  routes = [
    ['authenticate', { 'methodId' => 'token' }, :authenticate, ACP::Types::AuthenticateRequest],
    ['session/new', { 'cwd' => '/work', 'mcpServers' => [] }, :new_session, ACP::Types::NewSessionRequest],
    ['session/prompt', { 'sessionId' => 's', 'prompt' => [] }, :prompt, ACP::Types::PromptRequest],
    [
      'session/load',
      { 'sessionId' => 's', 'cwd' => '/work', 'mcpServers' => [] },
      :load_session,
      ACP::Types::LoadSessionRequest
    ],
    ['session/list', {}, :list_sessions, ACP::Types::ListSessionsRequest],
    ['session/resume', { 'sessionId' => 's', 'cwd' => '/work' }, :resume_session, ACP::Types::ResumeSessionRequest],
    ['session/close', { 'sessionId' => 's' }, :close_session, ACP::Types::CloseSessionRequest],
    ['session/delete', { 'sessionId' => 's' }, :delete_session, ACP::Types::DeleteSessionRequest],
    ['logout', {}, :logout, ACP::Types::LogoutRequest],
    [
      'session/set_mode',
      { 'sessionId' => 's', 'modeId' => 'code' },
      :change_session_mode,
      ACP::Types::SetSessionModeRequest
    ],
    [
      'session/set_config_option',
      { 'sessionId' => 's', 'configId' => 'model', 'value' => 'fast' },
      :change_session_config_option,
      ACP::Types::SetSessionConfigOptionRequest
    ]
  ].freeze
  unstable_routes = [
    ['session/fork', { 'sessionId' => 's', 'cwd' => '/work' }, :fork_session, ACP::Types::Unstable::ForkSessionRequest],
    ['providers/list', {}, :list_providers, ACP::Types::Unstable::ListProvidersRequest],
    ['providers/set', set_provider, :set_provider, ACP::Types::Unstable::SetProviderRequest],
    [
      'providers/disable',
      { 'providerId' => 'anthropic' },
      :disable_provider,
      ACP::Types::Unstable::DisableProviderRequest
    ]
  ].freeze
  let(:reader) { Object.new }
  let(:transport) { AgentConnectionTransport.new(reader) }
  let(:logger) { FakeLogger.new }
  let(:token) { ACP::Types::AuthMethodAgent.new(id: 'token', name: 'Token') }
  let(:terminal_method) { ACP::Types::AuthMethod::Terminal.new(id: 'terminal', name: 'Terminal') }
  let(:bare) { ACP::Types::AgentCapabilities.new }
  let(:acp) do
    ACP::Types::AgentCapabilities.new(mcp_capabilities: ACP::Types::Unstable::McpCapabilities.new(acp: true))
  end
  let(:everything) do
    ACP::Types::Unstable::AgentCapabilities.new(
      load_session: true,
      auth: ACP::Types::AgentAuthCapabilities.new(logout: ACP::Types::LogoutCapabilities.new),
      providers: ACP::Types::Unstable::ProvidersCapabilities.new,
      session_capabilities: ACP::Types::Unstable::SessionCapabilities.new(
        list: ACP::Types::SessionListCapabilities.new,
        resume: ACP::Types::SessionResumeCapabilities.new,
        close: ACP::Types::SessionCloseCapabilities.new,
        delete: ACP::Types::SessionDeleteCapabilities.new,
        fork: ACP::Types::Unstable::SessionForkCapabilities.new
      )
    )
  end
  let(:mcp_request) do
    ACP::Types::Unstable::MessageMcpRequest.new(server_id: 'srv_1', request_id: 'mcp_1', method: 'tools/call')
  end

  def connection(agent, capabilities: bare, **)
    ACP::AgentConnection.new(transport:, capabilities:, logger:, **) do |client|
      @client = client
      agent
    end
  end

  def start(agent = AgentConnectionAgent.new, **)
    connection(agent, **).start
  end

  define_method(:answer) do |rpc_method, params|
    agent = AgentConnectionAgent.new(*optional, *per_session)
    start(agent, capabilities: everything, auth_methods: [token])
    [transport.requests.fetch(rpc_method).call(params), agent.calls.map { |name, request| [name, request.class] }]
  end

  def stable_only_routes(script)
    out, _err = Open3.capture3('bundle', 'exec', 'ruby', '-I', 'lib', '-e', <<~RUBY)
      require 'acp/sdk'
      require 'json'

      transport = Object.new
      def transport.start(requests:, notifications:)
        puts JSON.generate(requests.keys)
      end
      agent = Object.new
      def agent.new_session(_request); end
      def agent.prompt(_request); end
      def agent.cancel(_notification); end
      #{script}
      ACP::AgentConnection.new(transport:, capabilities:) { |_client| agent }.start
    RUBY
    JSON.parse(out)
  end

  describe '.new' do
    it 'refuses an extension request name without the underscore prefix' do
      assert_raises(ArgumentError) do
        connection(AgentConnectionAgent.new, extension_requests: { 'myapp/double' => ->(_params) {} })
      end
    end

    it 'refuses an extension notification name without the underscore prefix' do
      assert_raises(ArgumentError) do
        connection(AgentConnectionAgent.new, extension_notifications: { 'myapp/tick' => ->(_params) {} })
      end
    end
  end

  describe '#start' do
    it 'hands the factory a client that sends over the transport' do
      start
      @client.ext_notify('_myapp/event', { 'n' => 1 })

      assert_equal [ACP::AgentConnection::Client, 1], [@client.class, transport.sent.size]
    end

    it 'lets the client send mcp/message when mcpCapabilities.acp is advertised' do
      start(AgentConnectionAgent.new(:mcp_message_notification), capabilities: acp)
      @client.mcp_message(mcp_request)

      assert_equal 1, transport.sent.size
    end

    it 'keeps the client from sending mcp/message unless mcpCapabilities.acp is advertised' do
      start
      @client.mcp_message(mcp_request)

      assert_empty transport.sent
    end

    it 'refuses to start, naming the advertised methods the agent lacks' do
      capabilities = ACP::Types::AgentCapabilities.new(
        load_session: true,
        session_capabilities: ACP::Types::Unstable::SessionCapabilities.new(
          list: ACP::Types::SessionListCapabilities.new,
          fork: ACP::Types::Unstable::SessionForkCapabilities.new
        )
      )
      error = assert_raises(ArgumentError) { start(AgentConnectionAgent.new(:list_sessions), capabilities:) }

      assert_equal(
        ['initialize advertises methods the agent lacks: load_session, fork_session', nil],
        [error.message, transport.requests]
      )
    end

    it 'refuses to start without authenticate when only a terminal auth method is advertised' do
      error = assert_raises(ArgumentError) { start(auth_methods: [terminal_method]) }

      assert_equal 'initialize advertises methods the agent lacks: authenticate', error.message
    end

    it 'refuses to start when mcpCapabilities.acp is advertised without a notification handler' do
      error = assert_raises(ArgumentError) { start(capabilities: acp) }

      assert_equal(
        ['initialize advertises mcpCapabilities.acp but the agent lacks mcp_message_notification', nil],
        [error.message, transport.requests]
      )
    end

    it 'leaves out the optional routes initialize does not advertise, even when the agent defines them' do
      start(AgentConnectionAgent.new(*optional))

      assert_equal %w[initialize session/new session/prompt], transport.requests.keys
    end

    it 'routes every optional method initialize advertises' do
      start(AgentConnectionAgent.new(*optional), capabilities: everything, auth_methods: [token])

      assert_equal(
        %w[
          authenticate
          logout
          providers/disable
          providers/list
          providers/set
          session/close
          session/delete
          session/fork
          session/list
          session/load
          session/resume
        ],
        (transport.requests.keys - %w[initialize session/new session/prompt]).sort
      )
    end

    it 'routes session/set_mode and session/set_config_option when the agent defines them' do
      start(AgentConnectionAgent.new(*per_session))

      assert_equal(
        %w[initialize session/new session/prompt session/set_mode session/set_config_option],
        transport.requests.keys
      )
    end

    it 'routes only the per-session method the agent defines' do
      start(AgentConnectionAgent.new(:change_session_config_option))

      assert_equal %w[initialize session/new session/prompt session/set_config_option], transport.requests.keys
    end

    it 'adds the extension requests to the request routes' do
      double = ->(params) { params }
      start(extension_requests: { '_myapp/double' => double })

      assert_same double, transport.requests['_myapp/double']
    end

    it 'adds the extension notifications to the notification routes' do
      tick = ->(_params) {}
      start(extension_notifications: { '_myapp/tick' => tick })

      assert_same tick, transport.notifications['_myapp/tick']
    end

    it 'returns the reader thread the transport started' do
      assert_same reader, start
    end
  end

  describe 'request routes' do
    routes.each do |rpc_method, params, agent_method, type|
      it "parses #{rpc_method} and answers with the agent's #{agent_method}" do
        assert_equal [agent_method, [[agent_method, type]]], answer(rpc_method, params)
      end
    end
  end

  describe 'unstable request routes' do
    it 'starts without the unstable routes when the unstable types are not opted into' do
      keys = stable_only_routes(<<~RUBY)
        def agent.fork_session(_request); end
        def agent.list_providers(_request); end
        def agent.set_provider(_request); end
        def agent.disable_provider(_request); end
        capabilities = ACP::Types::AgentCapabilities.new
      RUBY

      assert_equal %w[initialize session/new session/prompt], keys
    end

    unstable_routes.each do |rpc_method, params, agent_method, type|
      it "parses #{rpc_method} and answers with the agent's #{agent_method}" do
        assert_equal [agent_method, [[agent_method, type]]], answer(rpc_method, params)
      end
    end
  end

  describe 'optional methods' do
    it 'does not probe the unstable capabilities when the unstable types are not opted into' do
      keys = stable_only_routes(<<~RUBY)
        capabilities = Struct.new(:session_capabilities, :providers).new(Struct.new(:fork).new(true), true)
      RUBY

      assert_equal %w[initialize session/new session/prompt], keys
    end
  end

  describe 'notification routes' do
    it 'routes only session/cancel unless mcpCapabilities.acp is advertised' do
      start(AgentConnectionAgent.new(:mcp_message_notification))

      assert_equal %w[session/cancel], transport.notifications.keys
    end

    it 'routes mcp/message as well when mcpCapabilities.acp is advertised' do
      start(AgentConnectionAgent.new(:mcp_message_notification), capabilities: acp)

      assert_equal %w[session/cancel mcp/message], transport.notifications.keys
    end
  end

  describe 'session/cancel' do
    it 'logs and drops params that do not parse' do
      agent = AgentConnectionAgent.new
      start(agent)
      error = ACP::Types.parse(ACP::Types::CancelNotification, {})
      transport.notifications.fetch('session/cancel').call({})

      assert_equal([[[:warn, "dropped malformed session/cancel: #{error.message}"]], []], [logger.drain, agent.calls])
    end

    it 'forwards the parsed notification to the agent' do
      agent = AgentConnectionAgent.new
      start(agent)
      transport.notifications.fetch('session/cancel').call({ 'sessionId' => 's' })

      assert_equal(
        [[[:cancel, ACP::Types::CancelNotification]], []],
        [agent.calls.map { |name, notification| [name, notification.class] }, logger.drain]
      )
    end
  end

  describe 'mcp/message' do
    it 'logs and drops params that do not parse' do
      agent = AgentConnectionAgent.new(:mcp_message_notification)
      start(agent, capabilities: acp)
      error = ACP::Types.parse(ACP::Types::Unstable::MessageMcpNotification, {})
      transport.notifications.fetch('mcp/message').call({})

      assert_equal([[[:warn, "dropped malformed mcp/message: #{error.message}"]], []], [logger.drain, agent.calls])
    end

    it 'forwards the parsed notification to the agent' do
      agent = AgentConnectionAgent.new(:mcp_message_notification)
      start(agent, capabilities: acp)
      params = { 'serverId' => 'srv_1', 'requestId' => 'mcp_1', 'method' => 'notifications/progress' }
      transport.notifications.fetch('mcp/message').call(params)

      assert_equal(
        [[[:mcp_message_notification, ACP::Types::Unstable::MessageMcpNotification]], []],
        [agent.calls.map { |name, notification| [name, notification.class] }, logger.drain]
      )
    end
  end

  describe 'malformed request params' do
    it 'answers a parse error with invalid params carrying its message, without calling the agent' do
      agent = AgentConnectionAgent.new
      start(agent)
      parse_error = assert_raises(ACP::Types::ParseError) { ACP::Types::PromptRequest.from_h({}) }
      reply = transport.requests.fetch('session/prompt').call({})

      assert_equal [ACP::RequestError.invalid_params([parse_error.message]).to_h, []], [reply.to_h, agent.calls]
    end
  end

  describe 'initialize' do
    def connect(client_capabilities = nil, **)
      start(**)
      params = { 'protocolVersion' => 1, 'clientCapabilities' => client_capabilities }.compact
      transport.requests.fetch('initialize').call(params)
    end

    it 'gives the client handle the capabilities the client sent' do
      connect({ 'terminal' => true })

      assert_equal({ 'terminal' => true }, @client.capabilities.to_h)
    end

    it 'gives the client handle empty capabilities when the client sent none' do
      connect

      assert_instance_of ACP::Types::ClientCapabilities, @client.capabilities
    end

    it 'answers with the protocol version, the capabilities and the agent info' do
      agent_info = ACP::Types::Implementation.new(name: 'agent', version: '1.0.0')
      response = connect(agent_info:)

      assert_equal(
        [ACP::Types::InitializeResponse, ACP::Protocol::PROTOCOL_VERSION, bare, agent_info],
        [response.class, response.protocol_version, response.agent_capabilities, response.agent_info]
      )
    end

    describe 'auth methods' do
      def advertised(auth_methods, client_capabilities = nil)
        start(AgentConnectionAgent.new(:authenticate), auth_methods:)
        params = { 'protocolVersion' => 1, 'clientCapabilities' => client_capabilities }.compact
        transport.requests.fetch('initialize').call(params).auth_methods
      end

      it 'advertises every auth method to a client with terminal auth' do
        methods = [token, terminal_method]

        assert_equal methods, advertised(methods, { 'auth' => { 'terminal' => true } })
      end

      it 'leaves the terminal auth methods out for a client without terminal auth' do
        assert_equal [token], advertised([token, terminal_method], { 'auth' => { 'terminal' => false } })
      end

      it 'leaves the terminal auth methods out for a client that sent no capabilities' do
        assert_equal [token], advertised([token, terminal_method])
      end

      it 'leaves out a terminal auth method given as a hash and keeps the other hashes' do
        agent_hash = { 'type' => 'agent', 'id' => 'token', 'name' => 'Token' }
        terminal_hash = { 'type' => 'terminal', 'id' => 'terminal', 'name' => 'Terminal' }

        assert_equal [agent_hash], advertised([agent_hash, terminal_hash])
      end
    end
  end

  describe 'session/new' do
    let(:response) { ACP::Types::NewSessionResponse.new(session_id: 'sess_1') }

    def new_session(agent)
      start(agent)
      transport.requests.fetch('session/new').call({ 'cwd' => '/work', 'mcpServers' => [] })
    end

    it 'answers with an error the agent returned, without the session_created hook' do
      error = ACP::RequestError.auth_required
      agent = AgentConnectionAgent.new(:session_created, replies: { new_session: error })

      assert_same error, new_session(agent)
    end

    it 'answers with the response alone when the agent has no session_created hook' do
      assert_same response, new_session(AgentConnectionAgent.new(replies: { new_session: response }))
    end

    it 'defers the session_created hook until after the reply' do
      agent = AgentConnectionAgent.new(:session_created, replies: { new_session: response })
      reply = new_session(agent)
      before = agent.calls.map(&:first)
      reply.after.call

      assert_equal(
        [ACP::Transport::Reply, response, [:new_session], [:session_created, response]],
        [reply.class, reply.result, before, agent.calls.last]
      )
    end
  end
end
