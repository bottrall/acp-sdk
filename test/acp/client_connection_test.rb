# frozen_string_literal: true

require 'test_helper'
require 'open3'
require 'rbconfig'
require 'timeout'
require_relative '../../examples/echo_agent'

class StubTransport
  attr_reader :requests, :notifications

  def initialize(response)
    @response = response
  end

  def start(requests: {}, notifications: {})
    @requests = requests
    @notifications = notifications
    Thread.new { nil }
  end

  def request(_method, _params = nil)
    @response
  end

  def notify(_method, _params = nil); end
end

class AuthAgent
  def initialize
    @authenticated = false
  end

  def authenticate(request)
    return ACP::RequestError.auth_required unless request.method_id == 'token'

    @authenticated = true
    ACP::Types::AuthenticateResponse.new
  end

  def logout(_request)
    return ACP::RequestError.auth_required unless @authenticated

    ACP::Types::LogoutResponse.new
  end
end

# Holds each request on @gate until released, so a stream stays open between
# two threads.
class GatedTransport
  attr_reader :entered, :notifications

  def initialize(response)
    @response = response
    @entered = Thread::Queue.new
    @gate = Thread::Queue.new
  end

  def start(requests: {}, notifications: {})
    @requests = requests
    @notifications = notifications
    Thread.new { nil }
  end

  def request(_method, _params = nil)
    @entered << true
    @gate.pop
    @response
  end

  def notify(_method, _params = nil); end

  def release
    @gate << true
  end
end

describe ACP::ClientConnection do
  def within(seconds = 2, &)
    Timeout.timeout(seconds, &)
  end

  def choose(option_id)
    ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id:))
  end

  def text(value)
    ACP::Types::ContentBlock::Text.new(text: value)
  end

  def new_session_request(cwd = '/work')
    ACP::Types::NewSessionRequest.new(cwd:, mcp_servers: [])
  end

  def prompt_request(session_id, *texts)
    ACP::Types::PromptRequest.new(session_id:, prompt: texts.map { |value| text(value) })
  end

  def summary(update)
    case update
    when ACP::Types::SessionUpdate::ToolCall then ['tool_call', update.title]
    else [update.to_h['sessionUpdate'], update.to_h.dig('content', 'text')]
    end
  end

  describe 'driving the echo agent over pipes' do
    before do
      agent_input, @client_output = IO.pipe
      @client_input, @agent_output = IO.pipe
      @pipes = [agent_input, @client_output, @client_input, @agent_output]
      @agent_reader = ACP::AgentConnection.new(
        transport: ACP::Transport::Stdio.new(input: agent_input, output: @agent_output),
        capabilities: EchoAgent::CAPABILITIES,
        agent_info: ACP::Types::Implementation.new(name: 'echo-agent', version: '1.0.0')
      ) { |client| EchoAgent.new(client:) }.start
      @updates = Thread::Queue.new
    end

    after do
      @client_output.close
      @agent_reader.join(2)
      @agent_output.close
      @client_reader&.join(2)
      @pipes.reject(&:closed?).each(&:close)
    end

    def start(&permission)
      connection = ACP::ClientConnection.new(
        transport: ACP::Transport::Stdio.new(input: @client_input, output: @client_output),
        permission:,
        updates: ->(notification) { @updates << notification }
      )
      @client_reader = connection.start
      connection
    end

    def allowing
      start { choose(EchoAgent::ALLOW) }
    end

    def new_session(connection, cwd = '/work')
      session_id = within { connection.session_new(new_session_request(cwd)) }.session_id
      within { @updates.pop }
      session_id
    end

    it 'sends initialize through connect' do
      connection = allowing
      response = within { connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1)) }

      assert_equal(
        [1, true, 'echo-agent'],
        [response.protocol_version, response.agent_capabilities.load_session, response.agent_info.name]
      )
    end

    it 'hands updates outside a prompt, such as the available commands, to the updates handler' do
      connection = allowing
      within do
        connection.connect(
          ACP::Types::InitializeRequest.new(
            protocol_version: 1, client_capabilities: ACP::Types::ClientCapabilities.new(terminal: true)
          )
        )
      end
      session_id = within { connection.session_new(new_session_request) }.session_id
      notification = within { @updates.pop }

      assert_equal(
        [session_id, ['run']],
        [notification.session_id, notification.update.available_commands.map(&:name)]
      )
    end

    it 'yields each update of a prompt turn as it arrives and returns the stop reason' do
      seen = Thread::Queue.new
      requests = []
      connection = start do |request|
        requests << request
        within { seen.pop }
        choose(EchoAgent::ALLOW)
      end
      session_id = new_session(connection)
      updates = []
      # The permission handler waits for the tool call to be yielded, so this
      # would time out if updates were only yielded once the turn ended.
      response = within do
        connection.session_prompt(prompt_request(session_id, 'hello', 'world')) do |update|
          updates << update
          seen << true
        end
      end

      assert_equal(
        [
          'end_turn',
          [['tool_call', 'Echo the prompt'], %w[agent_message_chunk hello], %w[agent_message_chunk world]],
          [[session_id, updates.first.tool_call_id]]
        ],
        [
          response.stop_reason,
          updates.map { |update| summary(update) },
          requests.map { |request| [request.session_id, request.tool_call.tool_call_id] }
        ]
      )
    end

    it 'skips the echo when the permission handler rejects' do
      connection = start { choose('reject') }
      session_id = new_session(connection)
      updates = []
      response = within { connection.session_prompt(prompt_request(session_id, 'hi')) { |update| updates << update } }

      assert_equal(
        ['end_turn', [['tool_call', 'Echo the prompt']]],
        [response.stop_reason, updates.map { |update| summary(update) }]
      )
    end

    it 'returns the error a permission handler answers with as the prompt error' do
      error = ACP::RequestError.new(code: -32_000, message: 'No user')
      connection = start { error }
      session_id = new_session(connection)
      response = within { connection.session_prompt(prompt_request(session_id, 'hello')) { nil } }

      assert_equal(error.to_h, response.to_h)
    end

    it 'cancels a turn with session_cancel' do
      cancelled = Thread::Queue.new
      connection = start do
        within { cancelled.pop }
        choose(EchoAgent::ALLOW)
      end
      session_id = new_session(connection)
      response = within do
        connection.session_prompt(prompt_request(session_id, 'hello')) do
          connection.session_cancel(ACP::Types::CancelNotification.new(session_id:))
          cancelled << true
        end
      end

      assert_equal 'cancelled', response.stop_reason
    end

    it 'yields the replayed history from session_load' do
      connection = allowing
      session_id = new_session(connection)
      within { connection.session_prompt(prompt_request(session_id, 'hello')) { nil } }
      updates = []
      request = ACP::Types::LoadSessionRequest.new(session_id:, cwd: '/work', mcp_servers: [])
      response = within { connection.session_load(request) { |update| updates << update } }

      assert_equal(
        [{}, [%w[user_message_chunk hello], %w[agent_message_chunk hello]]],
        [response.to_h, updates.map { |update| summary(update) }]
      )
    end

    it 'lists sessions, filtered by cwd when given' do
      connection = allowing
      first = new_session(connection, '/a')
      new_session(connection, '/b')
      response = within { connection.session_list(ACP::Types::ListSessionsRequest.new(cwd: '/a')) }

      assert_equal([[first, '/a']], response.sessions.map { |info| [info.session_id, info.cwd] })
    end

    it 'returns the agent\'s error response' do
      connection = allowing
      response = within { connection.session_prompt(prompt_request('sess_missing', 'hello')) { nil } }

      assert_equal({ 'code' => -32_002, 'message' => 'Resource not found' }, response.to_h)
    end
  end

  describe 'driving an agent with auth over pipes' do
    before do
      agent_input, @client_output = IO.pipe
      @client_input, @agent_output = IO.pipe
      @pipes = [agent_input, @client_output, @client_input, @agent_output]
      agent = ACP::AgentConnection.new(
        transport: ACP::Transport::Stdio.new(input: agent_input, output: @agent_output),
        capabilities: ACP::Types::AgentCapabilities.new(
          auth: ACP::Types::AgentAuthCapabilities.new(logout: ACP::Types::LogoutCapabilities.new)
        ),
        agent_info: ACP::Types::Implementation.new(name: 'auth-agent', version: '1.0.0'),
        auth_methods: [ACP::Types::AuthMethodAgent.new(id: 'token', name: 'Token')]
      ) { AuthAgent.new }
      @agent_reader = agent.start
      @connection = ACP::ClientConnection.new(
        transport: ACP::Transport::Stdio.new(input: @client_input, output: @client_output),
        permission: ->(_request) {}
      )
      @client_reader = @connection.start
    end

    after do
      @client_output.close
      @agent_reader.join(2)
      @agent_output.close
      @client_reader.join(2)
      @pipes.reject(&:closed?).each(&:close)
    end

    def authenticate(method_id = 'token')
      within { @connection.authenticate(ACP::Types::AuthenticateRequest.new(method_id:)) }
    end

    def logout
      within { @connection.logout(ACP::Types::LogoutRequest.new) }
    end

    it 'authenticates' do
      assert_equal({}, authenticate.to_h)
    end

    it 'returns the agent\'s error when it rejects the auth method' do
      response = authenticate('bad')

      assert_equal({ 'code' => -32_000, 'message' => 'Authentication required' }, response.to_h)
    end

    it 'logs out after authenticating' do
      authenticate

      assert_equal({}, logout.to_h)
    end

    it 'returns the agent\'s error when logout comes before authenticate' do
      response = logout

      assert_equal({ 'code' => -32_000, 'message' => 'Authentication required' }, response.to_h)
    end
  end

  describe 'two overlapping streams for one session' do
    def connection(transport)
      connection = ACP::ClientConnection.new(transport:, permission: ->(_request) {})
      connection.start
      connection
    end

    it 'refuses the second call and leaves the first stream intact' do
      transport = GatedTransport.new({})
      conn = connection(transport)
      first_updates = []
      second_updates = []
      first = Thread.new do
        conn.session_prompt(prompt_request('s1', 'hello')) { |update| first_updates << update }
      end
      transport.entered.pop
      error = within { conn.session_prompt(prompt_request('s1', 'again')) { |update| second_updates << update } }

      assert_equal [-32_600, 'A stream is already open for session s1'], [error.code, error.message]

      transport.notifications['session/update'].call(
        'sessionId' => 's1',
        'update' => { 'sessionUpdate' => 'agent_message_chunk', 'content' => { 'type' => 'text', 'text' => 'hello' } }
      )
      transport.release
      response = within { first.value }

      assert_equal(
        [[-32_603, 'Invalid response', {}], [%w[agent_message_chunk hello]], []],
        [
          [response.code, response.message, response.data],
          first_updates.map { |update| summary(update) },
          second_updates
        ]
      )
    end

    it 'accepts a new stream for the session once the first one ends' do
      transport = GatedTransport.new({})
      conn = connection(transport)
      first = Thread.new do
        conn.session_prompt(prompt_request('s1', 'hello')) { nil }
      end
      transport.entered.pop
      transport.release
      within { first.value }
      # first cannot return before its requester thread removed the session
      # from @streams, so the next call must be accepted.
      transport.release
      response = within { conn.session_prompt(prompt_request('s1', 'again')) { nil } }

      assert_equal [-32_603, 'Invalid response', {}], [response.code, response.message, response.data]
    end
  end

  describe 'a malformed agent response' do
    def connection(result)
      ACP::ClientConnection.new(transport: StubTransport.new(result), permission: ->(_request) {})
    end

    it 'answers a reply missing a required key with invalid response' do
      error = within { connection({}).session_new(new_session_request) }

      assert_equal [-32_603, 'Invalid response', {}], [error.code, error.message, error.data]
    end

    it 'answers a reply with a wrongly shaped value with invalid response' do
      response = { 'sessionId' => 's', 'modes' => [] }
      error = within { connection(response).session_new(new_session_request) }

      assert_same response, error.data
      assert_equal [-32_603, 'Invalid response'], [error.code, error.message]
    end

    it 'answers a null result with invalid response' do
      error = within { connection(nil).session_new(new_session_request) }

      assert_equal [-32_603, 'Invalid response', nil], [error.code, error.message, error.data]
    end
  end

  describe 'an unsupported protocol version' do
    it 'answers an initialize reply naming a version the SDK does not speak with an error naming both' do
      connection = ACP::ClientConnection.new(
        transport: StubTransport.new({ 'protocolVersion' => 2 }), permission: ->(_request) {}
      )
      error = within { connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1)) }

      assert_equal([-32_603, 'Unsupported protocol version: requested 1, returned 2'], [error.code, error.message])
    end
  end

  describe 'a malformed session/update notification' do
    def connection
      transport = StubTransport.new({})
      logger = FakeLogger.new
      ACP::ClientConnection.new(transport:, permission: ->(_request) {}, logger:).start
      [transport, logger]
    end

    it 'logs and drops the notification' do
      transport, logger = connection
      transport.notifications['session/update'].call({ 'update' => { 'sessionUpdate' => 'agent_message_chunk' } })

      assert_equal [:warn, 'dropped malformed session/update: KeyError: key not found: "sessionId"'], logger.pop
    end
  end

  it 'drives the echo agent in a spawned subprocess' do
    stdin, stdout, wait = Open3.popen2(RbConfig.ruby, File.expand_path('../../examples/echo_agent.rb', __dir__))
    begin
      connection = ACP::ClientConnection.new(
        transport: ACP::Transport::Stdio.new(input: stdout, output: stdin),
        permission: ->(_request) { choose(EchoAgent::ALLOW) }
      )
      reader = connection.start
      texts = within(10) do
        connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1))
        session_id = connection.session_new(new_session_request).session_id
        chunks = []
        connection.session_prompt(prompt_request(session_id, 'hello')) do |update|
          chunks << update.content.text if update.is_a?(ACP::Types::SessionUpdate::AgentMessageChunk)
        end
        chunks
      end

      assert_equal ['hello'], texts
    ensure
      stdin.close
      Process.kill('KILL', wait.pid) unless wait.join(5)
      wait.join
      reader&.join(2)
      stdout.close
    end
  end
end
