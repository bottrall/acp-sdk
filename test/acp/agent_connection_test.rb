# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'open3'
require 'timeout'
require_relative '../../examples/echo_agent'

require 'acp/types/unstable'

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

  def fork_session(request)
    ACP::Types::Unstable::ForkSessionResponse.new(session_id: "forked-#{request.session_id}")
  end

  def list_providers(_request)
    ACP::Types::Unstable::ListProvidersResponse.new(
      providers: [ACP::Types::Unstable::ProviderInfo.new(
        provider_id: 'anthropic', supported: ['anthropic'], required: false
      )]
    )
  end

  # define_method, not def: the name is the wire-mandated set_provider, which
  # Naming/AccessorMethodName would flag on a def with one required argument.
  define_method(:set_provider) do |_request|
    ACP::Types::Unstable::SetProviderResponse.new
  end

  def disable_provider(_request)
    ACP::Types::Unstable::DisableProviderResponse.new
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

# Sends one mcp/message request per prompt turn and records the reply it gets,
# so the test can inspect the parsed outcome; the prompt text is otherwise
# unused.
class McpAgent < SimpleDelegator
  attr_reader :reply, :notifications

  def initialize(agent, client)
    super(agent)
    @client = client
    @notifications = []
  end

  def prompt(_request)
    @reply = @client.mcp_message(
      ACP::Types::Unstable::MessageMcpRequest.new(
        server_id: 'srv_1', request_id: 'mcp_1', method: 'tools/call', params: { 'name' => 'echo' }
      )
    )
    ACP::Types::PromptResponse.new(stop_reason: 'end_turn')
  end

  def mcp_message_notification(notification)
    @notifications << notification
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

  def fork_capabilities
    ACP::Types::AgentCapabilities.new(
      session_capabilities: ACP::Types::Unstable::SessionCapabilities.new(
        fork: ACP::Types::Unstable::SessionForkCapabilities.new
      )
    )
  end

  def providers_capabilities
    ACP::Types::Unstable::AgentCapabilities.new(providers: ACP::Types::Unstable::ProvidersCapabilities.new)
  end

  def acp_capabilities
    ACP::Types::AgentCapabilities.new(mcp_capabilities: ACP::Types::Unstable::McpCapabilities.new(acp: true))
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
    mcp: false,
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
      agent = McpAgent.new(agent, client) if mcp
      @mcp_agent = agent if mcp
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

    assert_equal [:warn, 'dropped malformed session/cancel: ACP::Types::ParseError: sessionId: is required'],
                 @logger.pop
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

  it 'routes session/fork when its capability is advertised' do
    start(capabilities: fork_capabilities)
    reply = call('session/fork', { 'sessionId' => 's', 'cwd' => '/work' })

    assert_equal({ 'sessionId' => 'forked-s' }, reply['result'])
  end

  it 'answers session/fork with method not found unless advertised' do
    start
    reply = call('session/fork', { 'sessionId' => 's', 'cwd' => '/work' })

    assert_equal(-32_601, reply.dig('error', 'code'))
  end

  it 'answers session/fork with method not found when the unstable types are not opted into' do
    out, _err = Open3.capture3('bundle', 'exec', 'ruby', '-I', 'lib', '-e', <<~RUBY)
      require 'acp/sdk'
      require 'json'
      require 'timeout'

      input, peer_writer = IO.pipe
      peer_reader, output = IO.pipe
      transport = ACP::Transport::Stdio.new(input:, output:, logger: ACP::Transport::StderrLogger.new)
      agent = Object.new
      def agent.new_session(_request)
        ACP::Types::NewSessionResponse.new(session_id: 'sess_new')
      end
      def agent.prompt(_request)
        ACP::Types::PromptResponse.new(stop_reason: 'end_turn')
      end
      def agent.cancel(_notification); end
      def agent.fork_session(_request)
        ACP::Types::NewSessionResponse.new(session_id: 'sess_forked')
      end
      connection = ACP::AgentConnection.new(transport:, capabilities: ACP::Types::AgentCapabilities.new) { |_client| agent }
      connection.start

      def read_message(reader)
        Timeout.timeout(2) { JSON.parse(reader.gets) }
      end

      peer_writer.puts(JSON.generate(
        'jsonrpc' => '2.0', 'id' => 1, 'method' => 'initialize', 'params' => { 'protocolVersion' => 1 }
      ))
      initialized = read_message(peer_reader)
      peer_writer.puts(JSON.generate(
        'jsonrpc' => '2.0', 'id' => 2, 'method' => 'session/fork',
        'params' => { 'sessionId' => 's', 'cwd' => '/work' }
      ))
      forked = read_message(peer_reader)

      puts JSON.generate(initialized: !initialized['result'].nil?, fork_error: forked.dig('error', 'code'))
    RUBY
    result = JSON.parse(out)

    assert_equal({ 'initialized' => true, 'fork_error' => -32_601 }, result)
  end

  it 'routes providers/list, providers/set and providers/disable when the providers capability is advertised' do
    start(capabilities: providers_capabilities)
    set_params = { 'providerId' => 'anthropic', 'apiType' => 'anthropic', 'baseUrl' => 'https://api.example.com' }
    replies = [
      call('providers/list', {}),
      call('providers/set', set_params),
      call('providers/disable', { 'providerId' => 'anthropic' })
    ]

    assert_equal(
      [
        { 'providers' => [{ 'providerId' => 'anthropic', 'supported' => ['anthropic'], 'required' => false }] },
        {},
        {}
      ],
      replies.map { |reply| reply['result'] }
    )
  end

  it 'answers providers/list, providers/set and providers/disable with method not found unless advertised' do
    start
    set_params = { 'providerId' => 'anthropic', 'apiType' => 'anthropic', 'baseUrl' => 'https://api.example.com' }
    replies = [
      call('providers/list', {}),
      call('providers/set', set_params),
      call('providers/disable', { 'providerId' => 'anthropic' })
    ]

    assert_equal([-32_601] * 3, replies.map { |reply| reply.dig('error', 'code') })
  end

  it 'answers the provider methods with method not found when the unstable types are not opted into' do
    out, _err = Open3.capture3('bundle', 'exec', 'ruby', '-I', 'lib', '-e', <<~RUBY)
      require 'acp/sdk'
      require 'json'
      require 'timeout'

      input, peer_writer = IO.pipe
      peer_reader, output = IO.pipe
      transport = ACP::Transport::Stdio.new(input:, output:, logger: ACP::Transport::StderrLogger.new)
      agent = Object.new
      def agent.new_session(_request)
        ACP::Types::NewSessionResponse.new(session_id: 'sess_new')
      end
      def agent.prompt(_request)
        ACP::Types::PromptResponse.new(stop_reason: 'end_turn')
      end
      def agent.cancel(_notification); end
      def agent.list_providers(_request)
        ACP::Types::Unstable::ListProvidersResponse.new(providers: [])
      end
      def agent.set_provider(_request)
        ACP::Types::Unstable::SetProviderResponse.new
      end
      def agent.disable_provider(_request)
        ACP::Types::Unstable::DisableProviderResponse.new
      end
      connection = ACP::AgentConnection.new(transport:, capabilities: ACP::Types::AgentCapabilities.new) { |_client| agent }
      connection.start

      def read_message(reader)
        Timeout.timeout(2) { JSON.parse(reader.gets) }
      end

      peer_writer.puts(JSON.generate(
        'jsonrpc' => '2.0', 'id' => 1, 'method' => 'initialize', 'params' => { 'protocolVersion' => 1 }
      ))
      initialized = read_message(peer_reader)
      replies = ['providers/list', 'providers/set', 'providers/disable'].each_with_index.map do |method, id|
        peer_writer.puts(JSON.generate('jsonrpc' => '2.0', 'id' => id + 2, 'method' => method, 'params' => {}))
        read_message(peer_reader)
      end

      puts JSON.generate(
        { initialized: !initialized['result'].nil? }.merge(
          replies.each_with_index.to_h { |reply, index| ["provider_\#{index}_error", reply.dig('error', 'code')] }
        )
      )
    RUBY
    result = JSON.parse(out)

    assert_equal(
      {
        'initialized' => true,
        'provider_0_error' => -32_601,
        'provider_1_error' => -32_601,
        'provider_2_error' => -32_601
      },
      result
    )
  end

  describe 'mcp/message' do
    # A prompt turn whose reply is used as the barrier for the agent's own
    # mcp/message send.
    def mcp_turn
      start(capabilities: acp_capabilities, mcp: true)
      connect({})
      session_id = new_session
      send_request('session/prompt', { 'sessionId' => session_id, 'prompt' => [text('mcp')] })
      request = receive_message
      [session_id, request]
    end

    it 'sends mcp/message to the client when mcpCapabilities.acp is advertised' do
      _session_id, request = mcp_turn
      send_message(
        { 'jsonrpc' => '2.0', 'id' => request.fetch('id'), 'result' => { 'result' => { 'content' => [] } } }
      )
      receive_message

      assert_equal(
        ['mcp/message',
         { 'serverId' => 'srv_1', 'requestId' => 'mcp_1', 'method' => 'tools/call', 'params' => { 'name' => 'echo' } }],
        [request['method'], request['params']]
      )
      assert_equal({ 'content' => [] }, @mcp_agent.reply.result)
    end

    it 'parses an explicit null result as a present result' do
      _session_id, request = mcp_turn
      send_message({ 'jsonrpc' => '2.0', 'id' => request.fetch('id'), 'result' => { 'result' => nil } })
      receive_message

      assert_instance_of ACP::Types::Unstable::MessageMcpResponse::Result, @mcp_agent.reply
      assert_nil @mcp_agent.reply.result
    end

    it 'parses an inner MCP error carrier' do
      _session_id, request = mcp_turn
      error = { 'code' => -32_602, 'message' => 'Unknown tool', 'data' => { 'name' => 'echo' } }
      send_message({ 'jsonrpc' => '2.0', 'id' => request.fetch('id'), 'result' => { 'error' => error } })
      receive_message

      assert_equal(
        [-32_602, 'Unknown tool', { 'name' => 'echo' }],
        [@mcp_agent.reply.error.code, @mcp_agent.reply.error.message, @mcp_agent.reply.error.data]
      )
    end

    it 'refuses mcp/message without a round trip unless mcpCapabilities.acp is advertised' do
      start(mcp: true)
      connect({})
      session_id = new_session
      send_request('session/prompt', { 'sessionId' => session_id, 'prompt' => [text('mcp')] })
      reply = receive_message

      assert_equal(
        [-32_601, 'Agent does not advertise mcpCapabilities.acp', 'end_turn'],
        [@mcp_agent.reply.code, @mcp_agent.reply.message, reply.dig('result', 'stopReason')]
      )
    end

    it 'routes mcp/message notifications to the agent when advertised' do
      start(capabilities: acp_capabilities, mcp: true)
      connect({})
      session_id = new_session
      send_message(
        { 'jsonrpc' => '2.0', 'method' => 'mcp/message',
          'params' => { 'serverId' => 'srv_1', 'requestId' => 'mcp_1', 'method' => 'notifications/progress',
                        'params' => { 'progress' => 1 } } }
      )
      call('session/set_mode', { 'sessionId' => session_id, 'modeId' => 'code' })

      assert_equal(
        [['srv_1', 'mcp_1', 'notifications/progress', { 'progress' => 1 }]],
        @mcp_agent.notifications.map do |notification|
          [notification.server_id, notification.request_id, notification.method, notification.params]
        end
      )
    end

    it 'drops mcp/message notifications when mcpCapabilities.acp is not advertised' do
      start(mcp: true)
      connect({})
      session_id = new_session
      send_message(
        { 'jsonrpc' => '2.0', 'method' => 'mcp/message',
          'params' => { 'serverId' => 'srv_1', 'requestId' => 'mcp_1', 'method' => 'notifications/progress' } }
      )
      call('session/set_mode', { 'sessionId' => session_id, 'modeId' => 'code' })

      assert_equal [], @mcp_agent.notifications
    end

    it 'refuses to start when mcpCapabilities.acp is advertised without a notification handler' do
      error = assert_raises(ArgumentError) { start(capabilities: acp_capabilities) }

      assert_equal(
        'initialize advertises mcpCapabilities.acp but the agent lacks mcp_message_notification',
        error.message
      )
    end
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

    assert_equal(
      { 'code' => -32_601, 'message' => 'Method not found', 'data' => { 'method' => 'authenticate' } },
      reply['error']
    )
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

    assert_equal(
      { 'code' => -32_601, 'message' => 'Method not found', 'data' => { 'method' => 'logout' } },
      reply['error']
    )
  end

  it 'answers session/load and session/list with method not found unless advertised' do
    start(capabilities: ACP::Types::AgentCapabilities.new)
    replies = [
      call('session/load', { 'sessionId' => 's', 'cwd' => '/work', 'mcpServers' => [] }),
      call('session/list', {})
    ]

    assert_equal([-32_601, -32_601], replies.map { |reply| reply.dig('error', 'code') })
  end

  it 'names the failing param path in the invalid params data' do
    start
    reply = call('session/prompt', { 'sessionId' => 42, 'prompt' => [text('hello')] })

    assert_equal(
      { 'code' => -32_602, 'message' => 'Invalid params',
        'data' => { 'errors' => ['sessionId: expected String, got Integer'] } },
      reply['error']
    )
  end

  it 'answers malformed params with invalid params' do
    start
    replies = [call('session/new', { 'mcpServers' => [] }), call('session/prompt'), call('initialize', [1])]

    assert_equal(
      [
        { 'code' => -32_602, 'message' => 'Invalid params', 'data' => { 'errors' => ['cwd: is required'] } },
        { 'code' => -32_602, 'message' => 'Invalid params' },
        { 'code' => -32_602, 'message' => 'Invalid params' }
      ],
      replies.map { |reply| reply['error'] }
    )
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

      assert_equal(
        { 'code' => -32_601, 'message' => 'Method not found', 'data' => { 'method' => '_myapp/unknown' } },
        call('_myapp/unknown').fetch('error')
      )
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
