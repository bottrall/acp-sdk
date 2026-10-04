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

class ModesAgent
  def change_session_mode(request)
    return ACP::RequestError.new(code: -32_000, message: 'No such mode') unless request.mode_id == 'code'

    ACP::Types::SetSessionModeResponse.new
  end

  def change_session_config_option(request)
    return ACP::RequestError.new(code: -32_000, message: 'No such option') unless request.config_id == 'thinking'

    ACP::Types::SetSessionConfigOptionResponse.new(config_options: [option(request.value.value)])
  end

  private

  def option(current_value)
    ACP::Types::SessionConfigOption.new(
      id: 'thinking', name: 'Thinking', kind: ACP::Types::SessionConfigOption::Kind::Boolean.new(current_value:)
    )
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

    it 'answers a pending permission request with cancelled after session_cancel' do
      entered = Thread::Queue.new
      release = Thread::Queue.new
      connection = start do |_request|
        entered << true
        release.pop
        choose(EchoAgent::ALLOW)
      end
      session_id = new_session(connection)
      response = within do
        connection.session_prompt(prompt_request(session_id, 'hello')) do
          # Entering the handler proves the request is registered, so the
          # cancel below cannot race ahead of it.
          within { entered.pop }
          connection.session_cancel(ACP::Types::CancelNotification.new(session_id:))
        end
      end

      assert_equal 'cancelled', response.stop_reason
    ensure
      release << true
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

    it 'resumes a session without replaying its history' do
      connection = allowing
      session_id = new_session(connection)
      within { connection.session_prompt(prompt_request(session_id, 'hello')) { nil } }
      response = within { connection.session_resume(ACP::Types::ResumeSessionRequest.new(session_id:, cwd: '/work')) }

      assert_equal([{}, true], [response.to_h, @updates.empty?])
    end

    it 'answers resume of an unknown session with the agent\'s error' do
      connection = allowing
      response = within do
        connection.session_resume(ACP::Types::ResumeSessionRequest.new(session_id: 'sess_missing', cwd: '/work'))
      end

      assert_equal({ 'code' => -32_002, 'message' => 'Resource not found' }, response.to_h)
    end

    it 'closes a session' do
      connection = allowing
      session_id = new_session(connection)
      response = within { connection.session_close(ACP::Types::CloseSessionRequest.new(session_id:)) }

      assert_equal({}, response.to_h)
    end

    it 'answers close of an unknown session with the agent\'s error' do
      connection = allowing
      response = within { connection.session_close(ACP::Types::CloseSessionRequest.new(session_id: 'sess_missing')) }

      assert_equal({ 'code' => -32_002, 'message' => 'Resource not found' }, response.to_h)
    end

    it 'deletes a session' do
      connection = allowing
      session_id = new_session(connection)
      response = within { connection.session_delete(ACP::Types::DeleteSessionRequest.new(session_id:)) }

      assert_equal({}, response.to_h)
    end

    it 'answers delete of an unknown session with the agent\'s error' do
      connection = allowing
      response = within { connection.session_delete(ACP::Types::DeleteSessionRequest.new(session_id: 'sess_missing')) }

      assert_equal({ 'code' => -32_002, 'message' => 'Resource not found' }, response.to_h)
    end

    it 'returns the agent\'s error response' do
      connection = allowing
      response = within { connection.session_prompt(prompt_request('sess_missing', 'hello')) { nil } }

      assert_equal({ 'code' => -32_002, 'message' => 'Resource not found' }, response.to_h)
    end
  end

  describe 'serving the agent\'s file requests' do
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
      @read_requests = Thread::Queue.new
      @write_requests = Thread::Queue.new
    end

    after do
      @client_output.close
      @agent_reader.join(2)
      @agent_output.close
      @client_reader&.join(2)
      @pipes.reject(&:closed?).each(&:close)
    end

    def start
      @read_replies = Thread::Queue.new
      @read_replies << ACP::Types::ReadTextFileResponse.new(content: 'hello')
      @write_replies = Thread::Queue.new
      @write_replies << ACP::Types::WriteTextFileResponse.new
      connection = ACP::ClientConnection.new(
        transport: ACP::Transport::Stdio.new(input: @client_input, output: @client_output),
        permission: ->(_request) { choose(EchoAgent::ALLOW) },
        read_text_file: method(:serve_read),
        write_text_file: method(:serve_write),
        updates: ->(notification) { @updates << notification }
      )
      @client_reader = connection.start
      connection
    end

    def serve_read(request)
      @read_requests << request
      @read_replies.pop
    end

    def serve_write(request)
      @write_requests << request
      @write_replies.pop
    end

    def connect(connection)
      within do
        connection.connect(
          ACP::Types::InitializeRequest.new(
            protocol_version: 1,
            client_capabilities: ACP::Types::ClientCapabilities.new(
              fs: ACP::Types::FileSystemCapabilities.new(read_text_file: true, write_text_file: true)
            )
          )
        )
      end
    end

    def new_session(connection)
      session_id = within { connection.session_new(new_session_request) }.session_id
      within { @updates.pop }
      session_id
    end

    it 'serves fs/read_text_file when connect advertises it' do
      connection = start
      connect(connection)
      session_id = new_session(connection)
      updates = []
      response = within do
        connection.session_prompt(prompt_request(session_id, '/read /a.txt')) { |update| updates << update }
      end

      assert_equal(
        ['/a.txt', [['tool_call', 'Echo the prompt'], ['agent_message_chunk', 'hello']], 'end_turn'],
        [@read_requests.pop.path, updates.map { |update| summary(update) }, response.stop_reason]
      )
    end

    it 'serves fs/write_text_file when connect advertises it' do
      connection = start
      connect(connection)
      session_id = new_session(connection)
      response = within { connection.session_prompt(prompt_request(session_id, '/write /a.txt hello')) { nil } }
      written = within { @write_requests.pop }

      assert_equal(['/a.txt', 'hello', 'end_turn'], [written.path, written.content, response.stop_reason])
    end

    it 'returns the error a file handler answers with as the prompt error' do
      connection = start
      @read_replies.clear
      @read_replies << ACP::RequestError.resource_not_found
      connect(connection)
      session_id = new_session(connection)
      response = within { connection.session_prompt(prompt_request(session_id, '/read /missing')) { nil } }

      assert_equal({ 'code' => -32_002, 'message' => 'Resource not found' }, response.to_h)
    end
  end

  describe 'answering file requests the capabilities do not advertise' do
    before do
      @client_input, @agent_output = IO.pipe
      @agent_input, @client_output = IO.pipe
      @connection = ACP::ClientConnection.new(
        transport: ACP::Transport::Stdio.new(input: @client_input, output: @client_output),
        permission: ->(_request) {},
        read_text_file: ->(_request) { ACP::Types::ReadTextFileResponse.new(content: 'hello') },
        write_text_file: ->(_request) { ACP::Types::WriteTextFileResponse.new }
      )
      @reader = @connection.start
    end

    after do
      @agent_output.close
      @reader.join(2)
      [@client_input, @client_output, @agent_input].reject(&:closed?).each(&:close)
    end

    # Plays the agent: a raw request into the client's input, its raw reply back.
    def reply_for(method, params)
      @agent_output.write("#{JSON.generate('jsonrpc' => '2.0', 'id' => 1, 'method' => method, 'params' => params)}\n")
      within { JSON.parse(@agent_input.gets) }
    end

    it 'answers -32601 before connect records any capability' do
      reply = reply_for('fs/read_text_file', { 'sessionId' => 's', 'path' => '/a.txt' })

      assert_equal(
        [-32_601, 'Client does not advertise fs.readTextFile'],
        [reply.dig('error', 'code'), reply.dig('error', 'message')]
      )
    end

    it 'answers -32601 for a method the advertised capabilities omit' do
      connect = Thread.new do
        @connection.connect(
          ACP::Types::InitializeRequest.new(
            protocol_version: 1,
            client_capabilities: ACP::Types::ClientCapabilities.new(
              fs: ACP::Types::FileSystemCapabilities.new(read_text_file: true)
            )
          )
        )
      end
      request = within { JSON.parse(@agent_input.gets) }
      result = JSON.generate('jsonrpc' => '2.0', 'id' => request['id'], 'result' => { 'protocolVersion' => 1 })
      @agent_output.write("#{result}\n")
      within { connect.value }
      reply = reply_for('fs/write_text_file', { 'sessionId' => 's', 'path' => '/a.txt', 'content' => 'hi' })

      assert_equal(
        [-32_601, 'Client does not advertise fs.writeTextFile'],
        [reply.dig('error', 'code'), reply.dig('error', 'message')]
      )
    end

    it 'refuses a connect that advertises a capability with no handler' do
      from_client, client_output = IO.pipe
      connection = ACP::ClientConnection.new(
        transport: ACP::Transport::Stdio.new(input: from_client, output: client_output),
        permission: ->(_request) {},
        read_text_file: ->(_request) { ACP::Types::ReadTextFileResponse.new(content: 'hello') }
      )
      error =
        within do
          assert_raises(ArgumentError) do
            connection.connect(
              ACP::Types::InitializeRequest.new(
                protocol_version: 1,
                client_capabilities: ACP::Types::ClientCapabilities.new(
                  fs: ACP::Types::FileSystemCapabilities.new(write_text_file: true)
                )
              )
            )
          end
        end

      assert_equal 'initialize advertises fs methods no handler serves: fs.writeTextFile', error.message
      assert_nil from_client.wait_readable(0.1), 'connect sent initialize anyway'
    ensure
      from_client&.close
      client_output&.close
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

  describe 'driving an agent with modes and config options over pipes' do
    before do
      agent_input, @client_output = IO.pipe
      @client_input, @agent_output = IO.pipe
      @pipes = [agent_input, @client_output, @client_input, @agent_output]
      agent = ACP::AgentConnection.new(
        transport: ACP::Transport::Stdio.new(input: agent_input, output: @agent_output),
        capabilities: ACP::Types::AgentCapabilities.new,
        agent_info: ACP::Types::Implementation.new(name: 'modes-agent', version: '1.0.0')
      ) { ModesAgent.new }
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

    def set_mode(mode_id = 'code')
      within do
        @connection.session_set_mode(ACP::Types::SetSessionModeRequest.new(session_id: 's1', mode_id:))
      end
    end

    def set_config_option(config_id, value)
      request = ACP::Types::SetSessionConfigOptionRequest.new(session_id: 's1', config_id:, value:)
      within { @connection.session_set_config_option(request) }
    end

    it 'sets the mode' do
      assert_equal({}, set_mode.to_h)
    end

    it 'returns the agent\'s error when it rejects the mode' do
      response = set_mode('ask')

      assert_equal({ 'code' => -32_000, 'message' => 'No such mode' }, response.to_h)
    end

    it 'sets a boolean config option and returns the complete option list' do
      response = set_config_option(
        'thinking',
        ACP::Types::SetSessionConfigOptionRequest::Value::Boolean.new(value: true)
      )

      assert_equal(
        [['thinking', 'Thinking', true]],
        response.config_options.map { |option| [option.id, option.name, option.kind.current_value] }
      )
    end

    it 'returns the agent\'s error when it rejects the config option' do
      response = set_config_option('modes', ACP::Types::SetSessionConfigOptionRequest::Value::ValueId.new(value: 'off'))

      assert_equal({ 'code' => -32_000, 'message' => 'No such option' }, response.to_h)
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

  describe 'extension methods' do
    before do
      agent_input, @client_output = IO.pipe
      @client_input, @agent_output = IO.pipe
      @pipes = [agent_input, @client_output, @client_input, @agent_output]
      @agent_notifications = Thread::Queue.new
      @client_notifications = Thread::Queue.new
      @agent_reader = ACP::AgentConnection.new(
        transport: ACP::Transport::Stdio.new(input: agent_input, output: @agent_output),
        capabilities: ACP::Types::AgentCapabilities.new,
        extension_requests: { '_myapp/double' => ->(params) { { 'doubled' => params.fetch('n') * 2 } } },
        extension_notifications: { '_myapp/tick' => ->(params) { @agent_notifications << params } }
      ) { |client| @agent_client = client }.start
    end

    after do
      @client_output.close
      @agent_reader.join(2)
      @agent_output.close
      @client_reader&.join(2)
      @pipes.reject(&:closed?).each(&:close)
    end

    def start
      connection = ACP::ClientConnection.new(
        transport: ACP::Transport::Stdio.new(input: @client_input, output: @client_output),
        permission: ->(_request) { raise 'no permission requests are expected' },
        extension_requests: { '_myapp/ping' => ->(params) { { 'echo' => params.fetch('n') } } },
        extension_notifications: { '_myapp/note' => ->(params) { @client_notifications << params } }
      )
      @client_reader = connection.start
      connection
    end

    it 'sends an extension request to the agent and returns its result' do
      connection = start

      assert_equal({ 'doubled' => 42 }, within { connection.ext_request('_myapp/double', { 'n' => 21 }) })
    end

    it 'sends an extension notification to the agent' do
      connection = start
      within { connection.ext_notify('_myapp/tick', { 'n' => 1 }) }

      assert_equal({ 'n' => 1 }, within { @agent_notifications.pop })
    end

    it "answers the agent's extension request through the registered handler" do
      start
      reply = Thread.new { @agent_client.ext_request('_myapp/ping', { 'n' => 'hello' }) }

      assert_equal({ 'echo' => 'hello' }, within { reply.value })
    end

    it 'routes an extension notification from the agent to the registered handler' do
      start
      within { @agent_client.ext_notify('_myapp/note', { 'n' => 1 }) }

      assert_equal({ 'n' => 1 }, within { @client_notifications.pop })
    end

    it 'answers an unregistered extension request with method not found' do
      connection = start
      error = within { connection.ext_request('_myapp/unknown') }
      from_agent = Thread.new { @agent_client.ext_request('_myapp/unknown') }

      assert_equal([-32_601, -32_601], [error.code, within { from_agent.value }.code])
    end

    it 'refuses extension handler names without the underscore prefix' do
      assert_raises(ArgumentError) do
        ACP::ClientConnection.new(
          transport: StubTransport.new(nil),
          permission: ->(_request) {},
          extension_requests: { 'myapp/ping' => ->(_params) {} }
        )
      end
      assert_raises(ArgumentError) do
        ACP::ClientConnection.new(
          transport: StubTransport.new(nil),
          permission: ->(_request) {},
          extension_notifications: { 'myapp/note' => ->(_params) {} }
        )
      end
      connection = start
      assert_raises(ArgumentError) { connection.ext_request('myapp/ping') }
      assert_raises(ArgumentError) { connection.ext_notify('myapp/note') }
    end
  end
end
