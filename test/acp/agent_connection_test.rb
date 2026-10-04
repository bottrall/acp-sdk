# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'timeout'
require_relative '../../examples/echo_agent'

class FullAgent < SimpleDelegator
  def authenticate(_request)
    ACP::Types::AuthenticateResponse.new
  end

  def resume_session(_request)
    ACP::Types::ResumeSessionResponse.new
  end

  def close_session(_request)
    ACP::Types::CloseSessionResponse.new
  end

  def delete_session(_request)
    ACP::Types::DeleteSessionResponse.new
  end

  def logout(_request)
    ACP::Types::LogoutResponse.new
  end

  def change_session_mode(_request)
    ACP::Types::SetSessionModeResponse.new
  end

  def change_session_config_option(_request)
    ACP::Types::SetSessionConfigOptionResponse.new(config_options: [])
  end
end

describe ACP::AgentConnection do
  let(:token) { ACP::Types::AuthMethodAgent.new(id: 'token', name: 'Token') }
  let(:terminal_method) { ACP::Types::AuthMethod::Terminal.new(id: 'terminal', name: 'Terminal') }
  let(:session_capabilities) do
    ACP::Types::AgentCapabilities.new(
      session_capabilities: ACP::Types::SessionCapabilities.new(
        resume: ACP::Types::SessionResumeCapabilities.new,
        close: ACP::Types::SessionCloseCapabilities.new,
        delete: ACP::Types::SessionDeleteCapabilities.new
      )
    )
  end

  before do
    @input, @peer_writer = IO.pipe
    @peer_reader, @output = IO.pipe
    @logger = FakeLogger.new
    @transport = ACP::Transport::Stdio.new(input: @input, output: @output, logger: @logger)
    @next_id = 0
  end

  after do
    @peer_writer.close unless @peer_writer.closed?
    @reader&.join(2)
    [@input, @output, @peer_reader].each(&:close)
  end

  def start(
    capabilities: EchoAgent::CAPABILITIES,
    auth_methods: [],
    full: true,
    extension_requests: {},
    extension_notifications: {}
  )
    agent_info = ACP::Types::Implementation.new(name: 'echo-agent', version: '1.0.0')
    connection = ACP::AgentConnection.new(
      transport: @transport,
      capabilities:,
      agent_info:,
      auth_methods:,
      extension_requests:,
      extension_notifications:,
      logger: @logger
    ) do |client|
      @client = client
      agent = EchoAgent.new(client:)
      full ? FullAgent.new(agent) : agent
    end
    @reader = connection.start
  end

  def send_message(message)
    @peer_writer.puts(JSON.generate(message))
  end

  def receive_message
    Timeout.timeout(2) { JSON.parse(@peer_reader.gets) }
  end

  def send_request(method, params = nil)
    id = @next_id += 1
    send_message({ 'jsonrpc' => '2.0', 'id' => id, 'method' => method, 'params' => params }.compact)
    id
  end

  def call(method, params = nil)
    send_request(method, params)
    receive_message
  end

  def new_session(cwd = '/work')
    session_id = call('session/new', { 'cwd' => cwd, 'mcpServers' => [] }).dig('result', 'sessionId')
    receive_message
    session_id
  end

  def text(value)
    { 'type' => 'text', 'text' => value }
  end

  def update_kind(message)
    message.dig('params', 'update', 'sessionUpdate')
  end

  def answer_permission(outcome)
    request = receive_message
    send_message({ 'jsonrpc' => '2.0', 'id' => request.fetch('id'), 'result' => { 'outcome' => outcome } })
    request
  end

  def echo_turn(session_id, *texts)
    send_request('session/prompt', { 'sessionId' => session_id, 'prompt' => texts.map { |value| text(value) } })
    receive_message
    answer_permission({ 'outcome' => 'selected', 'optionId' => EchoAgent::ALLOW })
    texts.each { receive_message }
    receive_message
  end

  it 'answers initialize and exposes the client capabilities on the handle' do
    start
    before_initialize = @client.capabilities
    capabilities = { 'fs' => { 'readTextFile' => true, 'writeTextFile' => false }, 'terminal' => true }
    reply = call('initialize', { 'protocolVersion' => 1, 'clientCapabilities' => capabilities })
    expected = {
      'protocolVersion' => 1,
      'agentCapabilities' => {
        'loadSession' => true,
        'sessionCapabilities' => { 'list' => {}, 'delete' => {}, 'resume' => {}, 'close' => {} }
      },
      'authMethods' => [],
      'agentInfo' => { 'name' => 'echo-agent', 'version' => '1.0.0' }
    }

    assert_equal [nil, expected, capabilities], [before_initialize, reply['result'], @client.capabilities.to_h]
  end

  it 'advertises terminal auth methods to clients that support them' do
    start(auth_methods: [token, terminal_method])
    reply = call('initialize', { 'protocolVersion' => 1, 'clientCapabilities' => { 'auth' => { 'terminal' => true } } })

    assert_equal %w[token terminal], auth_method_ids(reply)
  end

  it 'leaves terminal auth methods out for clients without terminal support' do
    start(auth_methods: [token, terminal_method])
    capabilities = { 'fs' => { 'readTextFile' => true, 'writeTextFile' => false } }
    reply = call('initialize', { 'protocolVersion' => 1, 'clientCapabilities' => capabilities })

    assert_equal %w[token], auth_method_ids(reply)
  end

  def auth_method_ids(reply)
    methods = reply['result']['authMethods']
    methods.map { |method| method['id'] }
  end

  it 'replies to session/new before sending the available commands' do
    start
    connect({ 'fs' => { 'readTextFile' => true, 'writeTextFile' => true }, 'terminal' => true })
    reply = call('session/new', { 'cwd' => '/work', 'mcpServers' => [] })
    update = receive_message
    commands = [
      ['read', 'Echo a file from the editor', 'path'],
      ['write', 'Write text to a file in the editor', 'path text'],
      ['run', 'Run a command in a terminal and echo its output', 'command [args]']
    ].map { |name, description, hint| { 'name' => name, 'description' => description, 'input' => { 'hint' => hint } } }

    assert_equal(
      [true, 'session/update', reply.dig('result', 'sessionId'), 'available_commands_update', commands],
      [
        reply.dig('result', 'sessionId').start_with?('sess_'),
        update['method'],
        update.dig('params', 'sessionId'),
        update_kind(update),
        update.dig('params', 'update', 'availableCommands')
      ]
    )
  end

  it 'advertises only the commands the client has the capabilities for' do
    start
    connect({ 'terminal' => true })
    call('session/new', { 'cwd' => '/work', 'mcpServers' => [] })

    commands = receive_message.dig('params', 'update', 'availableCommands')

    assert_equal(['run'], commands.map { |command| command['name'] })
  end

  it 'echoes the prompt once the client allows the tool call' do
    start
    session_id = new_session
    send_request('session/prompt', { 'sessionId' => session_id, 'prompt' => [text('hello'), text('world')] })
    tool_call = receive_message
    permission = answer_permission({ 'outcome' => 'selected', 'optionId' => EchoAgent::ALLOW })
    chunks = [receive_message, receive_message]

    assert_equal(
      [
        'tool_call',
        'session/request_permission',
        tool_call.dig('params', 'update', 'toolCallId'),
        [%w[agent_message_chunk hello], %w[agent_message_chunk world]],
        { 'stopReason' => 'end_turn' }
      ],
      [
        update_kind(tool_call),
        permission['method'],
        permission.dig('params', 'toolCall', 'toolCallId'),
        chunks.map { |chunk| [update_kind(chunk), chunk.dig('params', 'update', 'content', 'text')] },
        receive_message['result']
      ]
    )
  end

  def connect(capabilities)
    call('initialize', { 'protocolVersion' => 1, 'clientCapabilities' => capabilities })
  end

  def allowed_turn(session_id, prompt)
    send_request('session/prompt', { 'sessionId' => session_id, 'prompt' => [text(prompt)] })
    receive_message
    answer_permission({ 'outcome' => 'selected', 'optionId' => EchoAgent::ALLOW })
  end

  def answer(request, result)
    send_message({ 'jsonrpc' => '2.0', 'id' => request.fetch('id'), 'result' => result })
    request
  end

  it 'writes and reads a file through the client when it advertises fs' do
    start
    connect({ 'fs' => { 'readTextFile' => true, 'writeTextFile' => true } })
    session_id = new_session
    allowed_turn(session_id, '/write /work/notes.txt hello there')
    write = answer(receive_message, {})
    write_reply = receive_message
    allowed_turn(session_id, '/read /work/notes.txt')
    read = answer(receive_message, { 'content' => 'hello there' })
    chunk = receive_message

    assert_equal(
      [
        ['fs/write_text_file', { 'sessionId' => session_id, 'path' => '/work/notes.txt', 'content' => 'hello there' }],
        { 'stopReason' => 'end_turn' },
        ['fs/read_text_file', { 'sessionId' => session_id, 'path' => '/work/notes.txt' }],
        ['agent_message_chunk', 'hello there'],
        { 'stopReason' => 'end_turn' }
      ],
      [
        write.values_at('method', 'params'),
        write_reply['result'],
        read.values_at('method', 'params'),
        [update_kind(chunk), chunk.dig('params', 'update', 'content', 'text')],
        receive_message['result']
      ]
    )
  end

  it 'refuses file access the client did not advertise without a round trip' do
    start
    connect({ 'fs' => { 'readTextFile' => false } })
    session_id = new_session
    allowed_turn(session_id, '/write /work/notes.txt hello')
    write_reply = receive_message
    allowed_turn(session_id, '/read /work/notes.txt')

    assert_equal(
      [
        { 'code' => -32_601, 'message' => 'Client does not advertise fs.writeTextFile' },
        { 'code' => -32_601, 'message' => 'Client does not advertise fs.readTextFile' }
      ],
      [write_reply['error'], receive_message['error']]
    )
  end

  it 'runs a command in a terminal through the client when it advertises terminal' do
    start
    connect({ 'terminal' => true })
    session_id = new_session
    allowed_turn(session_id, %(/run echo 'hi there'))
    terminal = { 'sessionId' => session_id, 'terminalId' => 'term_1' }
    requests = [
      answer(receive_message, { 'terminalId' => 'term_1' }),
      answer(receive_message, { 'exitCode' => 0 }),
      answer(receive_message, { 'output' => "hi there\n", 'truncated' => false, 'exitStatus' => { 'exitCode' => 0 } }),
      answer(receive_message, {})
    ]
    chunk = receive_message

    assert_equal(
      [
        [
          ['terminal/create', { 'sessionId' => session_id, 'command' => 'echo', 'args' => ['hi there'] }],
          ['terminal/wait_for_exit', terminal],
          ['terminal/output', terminal],
          ['terminal/release', terminal]
        ],
        ['agent_message_chunk', "hi there\n"],
        { 'stopReason' => 'end_turn' }
      ],
      [
        requests.map { |request| request.values_at('method', 'params') },
        [update_kind(chunk), chunk.dig('params', 'update', 'content', 'text')],
        receive_message['result']
      ]
    )
  end

  it 'refuses a terminal the client did not advertise without a round trip' do
    start
    connect({ 'terminal' => false })
    session_id = new_session
    allowed_turn(session_id, '/run echo hi')

    assert_equal({ 'code' => -32_601, 'message' => 'Client does not advertise terminal' }, receive_message['error'])
  end

  it 'rejects a command line with an unmatched quote without a round trip' do
    start
    connect({ 'terminal' => true })
    session_id = new_session
    allowed_turn(session_id, %(/run echo 'hi))

    assert_equal({ 'code' => -32_602, 'message' => 'Invalid params' }, receive_message['error'])
  end

  it 'stops with cancelled when the turn is cancelled while permission is pending' do
    start
    session_id = new_session
    send_request('session/prompt', { 'sessionId' => session_id, 'prompt' => [text('hello')] })
    receive_message
    permission = receive_message
    send_message({ 'jsonrpc' => '2.0', 'method' => 'session/cancel', 'params' => { 'sessionId' => session_id } })
    cancelled = { 'outcome' => { 'outcome' => 'cancelled' } }
    send_message({ 'jsonrpc' => '2.0', 'id' => permission['id'], 'result' => cancelled })

    assert_equal({ 'stopReason' => 'cancelled' }, receive_message['result'])
  end

  it 'logs and drops a malformed session/cancel and keeps serving' do
    start
    send_message({ 'jsonrpc' => '2.0', 'method' => 'session/cancel', 'params' => {} })
    call('initialize', { 'protocolVersion' => 1, 'clientCapabilities' => {} })

    assert_equal [:warn, 'dropped malformed session/cancel: KeyError: key not found: "sessionId"'], @logger.pop
  end

  it 'lists sessions, filtered by cwd when given' do
    start
    first = new_session('/a')
    second = new_session('/b')
    all = call('session/list', {}).dig('result', 'sessions')
    filtered = call('session/list', { 'cwd' => '/a' }).dig('result', 'sessions')

    assert_equal(
      [[[first, '/a'], [second, '/b']].sort, [{ 'sessionId' => first, 'cwd' => '/a' }]],
      [all.map { |info| info.values_at('sessionId', 'cwd') }.sort, filtered]
    )
  end

  it 'replays the session history before replying to session/load' do
    start
    session_id = new_session
    echo_turn(session_id, 'hello')
    send_request('session/load', { 'sessionId' => session_id, 'cwd' => '/work', 'mcpServers' => [] })
    messages = [receive_message, receive_message, receive_message]

    assert_equal(
      [%w[user_message_chunk hello], %w[agent_message_chunk hello], {}],
      [
        *messages.first(2).map { |message| [update_kind(message), message.dig('params', 'update', 'content', 'text')] },
        messages.last['result']
      ]
    )
  end

  it 'answers session/load for an unknown session with resource not found' do
    start
    reply = call('session/load', { 'sessionId' => 'sess_missing', 'cwd' => '/work', 'mcpServers' => [] })

    assert_equal({ 'code' => -32_002, 'message' => 'Resource not found' }, reply['error'])
  end

  it 'answers unknown methods with method not found' do
    start
    reply = call('session/unknown', { 'sessionId' => 's' })

    assert_equal(-32_601, reply.dig('error', 'code'))
  end

  it 'routes session/resume, session/close and session/delete when their capabilities are advertised' do
    start(capabilities: session_capabilities)
    replies = [
      call('session/resume', { 'sessionId' => 's', 'cwd' => '/work' }),
      call('session/close', { 'sessionId' => 's' }),
      call('session/delete', { 'sessionId' => 's' })
    ]

    assert_equal([{}] * 3, replies.map { |reply| reply['result'] })
  end

  it 'answers session/resume, session/close and session/delete with method not found unless advertised' do
    # Not the echo agent's capabilities: it advertises all three now.
    start(capabilities: ACP::Types::AgentCapabilities.new(load_session: true))
    replies = [
      call('session/resume', { 'sessionId' => 's', 'cwd' => '/work' }),
      call('session/close', { 'sessionId' => 's' }),
      call('session/delete', { 'sessionId' => 's' })
    ]

    assert_equal([-32_601] * 3, replies.map { |reply| reply.dig('error', 'code') })
  end

  it 'routes session/set_mode and session/set_config_option when the agent defines them' do
    start
    replies = [
      call('session/set_mode', { 'sessionId' => 's', 'modeId' => 'code' }),
      call('session/set_config_option', { 'sessionId' => 's', 'configId' => 'model', 'value' => 'fast' })
    ]

    assert_equal([{}, { 'configOptions' => [] }], replies.map { |reply| reply['result'] })
  end

  it 'answers session/set_mode and session/set_config_option with method not found unless the agent defines them' do
    start(full: false)
    replies = [
      call('session/set_mode', { 'sessionId' => 's', 'modeId' => 'code' }),
      call('session/set_config_option', { 'sessionId' => 's', 'configId' => 'model', 'value' => 'fast' })
    ]

    assert_equal([-32_601] * 2, replies.map { |reply| reply.dig('error', 'code') })
  end

  it 'advertises its auth methods in initialize and authenticates' do
    start(auth_methods: [token])
    advertised = connect({}).dig('result', 'authMethods')
    reply = call('authenticate', { 'methodId' => 'token' })

    assert_equal([[{ 'id' => 'token', 'name' => 'Token' }], {}], [advertised, reply['result']])
  end

  it 'answers authenticate with method not found unless an auth method is advertised' do
    start
    reply = call('authenticate', { 'methodId' => 'token' })

    assert_equal({ 'code' => -32_601, 'message' => 'Method not found' }, reply['error'])
  end

  it 'routes logout when auth logout is advertised' do
    capabilities = ACP::Types::AgentCapabilities.new(
      auth: ACP::Types::AgentAuthCapabilities.new(logout: ACP::Types::LogoutCapabilities.new)
    )
    start(capabilities:)
    reply = call('logout', {})

    assert_equal({}, reply['result'])
  end

  it 'answers logout with method not found unless advertised' do
    start
    reply = call('logout', {})

    assert_equal({ 'code' => -32_601, 'message' => 'Method not found' }, reply['error'])
  end

  it 'answers session/load and session/list with method not found unless advertised' do
    start(capabilities: ACP::Types::AgentCapabilities.new)
    replies = [
      call('session/load', { 'sessionId' => 's', 'cwd' => '/work', 'mcpServers' => [] }),
      call('session/list', {})
    ]

    assert_equal([-32_601, -32_601], replies.map { |reply| reply.dig('error', 'code') })
  end

  it 'answers malformed params with invalid params' do
    start
    replies = [call('session/new', { 'mcpServers' => [] }), call('session/prompt'), call('initialize', [1])]

    assert_equal([{ 'code' => -32_602, 'message' => 'Invalid params' }] * 3, replies.map { |reply| reply['error'] })
  end

  it 'refuses to start when a capability is advertised without its method' do
    connection = ACP::AgentConnection.new(transport: @transport, capabilities: EchoAgent::CAPABILITIES) { Object.new }

    assert_raises(ArgumentError) { connection.start }
  end

  it 'refuses to start when a session capability is advertised without its method' do
    connection = ACP::AgentConnection.new(transport: @transport, capabilities: session_capabilities) { Object.new }

    assert_raises(ArgumentError) { connection.start }
  end

  it 'refuses to start when an auth method is advertised without authenticate' do
    capabilities = ACP::Types::AgentCapabilities.new
    connection = ACP::AgentConnection.new(transport: @transport, capabilities:, auth_methods: [token]) { Object.new }

    assert_raises(ArgumentError) { connection.start }
  end

  it 'refuses to start when auth logout is advertised without logout' do
    capabilities = ACP::Types::AgentCapabilities.new(
      auth: ACP::Types::AgentAuthCapabilities.new(logout: ACP::Types::LogoutCapabilities.new)
    )
    connection = ACP::AgentConnection.new(transport: @transport, capabilities:) { Object.new }

    assert_raises(ArgumentError) { connection.start }
  end

  describe 'extension methods' do
    it 'routes an extension request to the registered handler' do
      start(extension_requests: { '_myapp/double' => ->(params) { { 'doubled' => params.fetch('n') * 2 } } })

      assert_equal(
        { 'jsonrpc' => '2.0', 'id' => 1, 'result' => { 'doubled' => 42 } },
        call('_myapp/double', { 'n' => 21 })
      )
    end

    it 'routes an extension notification to the registered handler' do
      notifications = Thread::Queue.new
      start(extension_notifications: { '_myapp/tick' => ->(params) { notifications << params } })
      send_message({ 'jsonrpc' => '2.0', 'method' => '_myapp/tick', 'params' => { 'n' => 1 } })

      assert_equal({ 'n' => 1 }, Timeout.timeout(2) { notifications.pop })
    end

    it 'answers an unregistered extension request with method not found' do
      start

      assert_equal({ 'code' => -32_601, 'message' => 'Method not found' }, call('_myapp/unknown').fetch('error'))
    end

    it 'sends an extension request from the agent and returns the client\'s result' do
      start
      reply = Thread.new { @client.ext_request('_myapp/ping', { 'n' => 1 }) }
      request = receive_message
      send_message({ 'jsonrpc' => '2.0', 'id' => request.fetch('id'), 'result' => { 'pong' => 1 } })

      assert_equal({ 'pong' => 1 }, Timeout.timeout(2) { reply.value })
    end

    it 'sends an extension notification from the agent' do
      start
      @client.ext_notify('_myapp/event', { 'n' => 1 })

      assert_equal({ 'jsonrpc' => '2.0', 'method' => '_myapp/event', 'params' => { 'n' => 1 } }, receive_message)
    end

    it 'refuses extension handler names without the underscore prefix' do
      assert_raises(ArgumentError) do
        ACP::AgentConnection.new(
          transport: @transport,
          capabilities: ACP::Types::AgentCapabilities.new,
          extension_requests: { 'myapp/double' => ->(_params) {} }
        )
      end
      assert_raises(ArgumentError) do
        ACP::AgentConnection.new(
          transport: @transport,
          capabilities: ACP::Types::AgentCapabilities.new,
          extension_notifications: { 'myapp/tick' => ->(_params) {} }
        )
      end
      start
      assert_raises(ArgumentError) { @client.ext_request('myapp/ping') }
      assert_raises(ArgumentError) { @client.ext_notify('myapp/tick') }
    end
  end
end
