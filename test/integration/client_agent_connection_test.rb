# frozen_string_literal: true

require 'test_helper'
require 'timeout'
require_relative '../../examples/echo_agent'

describe 'a client connection driving an agent connection' do
  def within(seconds = 2, &)
    Timeout.timeout(seconds, &)
  end

  def choose(option_id)
    ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id:))
  end

  def new_session_request
    ACP::Types::NewSessionRequest.new(cwd: '/work', mcp_servers: [])
  end

  def prompt_request(session_id, *texts)
    ACP::Types::PromptRequest.new(
      session_id:, prompt: texts.map { |value| ACP::Types::ContentBlock::Text.new(text: value) }
    )
  end

  def summary(update)
    case update
    when ACP::Types::SessionUpdate::ToolCall then ['tool_call', update.title]
    else [update.to_h['sessionUpdate'], update.to_h.dig('content', 'text')]
    end
  end

  before do
    @agent_input, @client_output = IO.pipe
    @client_input, @agent_output = IO.pipe
    @updates = Thread::Queue.new
    @readers = []
  end

  after do
    @client_output.close
    @agent_output.close
    @readers.each { |reader| reader.join(2) }
    [@agent_input, @client_input].reject(&:closed?).each(&:close)
  end

  def start_agent(capabilities: EchoAgent::CAPABILITIES, **, &build)
    build ||= ->(client) { EchoAgent.new(client:) }
    @readers << ACP::AgentConnection.new(
      transport: ACP::Transport::Stdio.new(input: @agent_input, output: @agent_output, logger: FakeLogger.new),
      capabilities:,
      **,
      &build
    ).start
  end

  def start_client(permission: ->(_request) { choose(EchoAgent::ALLOW) }, **)
    connection = ACP::ClientConnection.new(
      transport: ACP::Transport::Stdio.new(input: @client_input, output: @client_output, logger: FakeLogger.new),
      permission:,
      updates: ->(notification) { @updates << notification },
      **
    )
    @readers << connection.start
    connection
  end

  def new_session(connection)
    session_id = within { connection.new_session(new_session_request) }.session_id
    within { @updates.pop }
    session_id
  end

  it 'hands updates outside a prompt, such as the available commands, to the updates handler' do
    start_agent
    connection = start_client(read_text_file: ->(_request) { ACP::Types::ReadTextFileResponse.new(content: '') })
    within do
      connection.connect(
        ACP::Types::InitializeRequest.new(
          protocol_version: 1,
          client_capabilities: ACP::Types::ClientCapabilities.new(
            fs: ACP::Types::FileSystemCapabilities.new(read_text_file: true)
          )
        )
      )
    end
    session_id = within { connection.new_session(new_session_request) }.session_id
    notification = within { @updates.pop }

    assert_equal(
      [session_id, ['read']],
      [notification.session_id, notification.update.available_commands.map(&:name)]
    )
  end

  it 'yields each update of a prompt turn as it arrives and returns the stop reason' do
    start_agent
    seen = Thread::Queue.new
    requests = []
    connection = start_client(
      permission: lambda do |request|
        requests << request
        within { seen.pop }
        choose(EchoAgent::ALLOW)
      end
    )
    session_id = new_session(connection)
    updates = []
    # The permission handler waits for the tool call to be yielded, so this
    # would time out if updates were only yielded once the turn ended.
    response = within do
      connection.prompt_session(prompt_request(session_id, 'hello', 'world')) do |update|
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

  it 'returns the error a permission handler answers with as the prompt error' do
    start_agent
    error = ACP::RequestError.new(code: -32_000, message: 'No user')
    connection = start_client(permission: ->(_request) { error })
    session_id = new_session(connection)
    response = within { connection.prompt_session(prompt_request(session_id, 'hello')) { nil } }

    assert_equal(error.to_h, response.to_h)
  end

  it 'yields the replayed history from load_session' do
    start_agent
    connection = start_client
    session_id = new_session(connection)
    within { connection.prompt_session(prompt_request(session_id, 'hello')) { nil } }
    updates = []
    request = ACP::Types::LoadSessionRequest.new(session_id:, cwd: '/work', mcp_servers: [])
    response = within { connection.load_session(request) { |update| updates << update } }

    assert_equal(
      [{}, [%w[user_message_chunk hello], %w[agent_message_chunk hello]]],
      [response.to_h, updates.map { |update| summary(update) }]
    )
  end

  it "returns the agent's error response" do
    start_agent
    connection = start_client
    response = within { connection.prompt_session(prompt_request('sess_missing', 'hello')) { nil } }

    assert_equal({ 'code' => -32_002, 'message' => 'Resource not found' }, response.to_h)
  end

  it "serves the agent's file read in the middle of a prompt turn" do
    start_agent
    reads = []
    connection = start_client(
      read_text_file: lambda do |request|
        reads << request.path
        ACP::Types::ReadTextFileResponse.new(content: 'hello')
      end
    )
    within do
      connection.connect(
        ACP::Types::InitializeRequest.new(
          protocol_version: 1,
          client_capabilities: ACP::Types::ClientCapabilities.new(
            fs: ACP::Types::FileSystemCapabilities.new(read_text_file: true)
          )
        )
      )
    end
    session_id = new_session(connection)
    updates = []
    response = within do
      connection.prompt_session(prompt_request(session_id, '/read /a.txt')) { |update| updates << update }
    end

    assert_equal(
      [['/a.txt'], [['tool_call', 'Echo the prompt'], %w[agent_message_chunk hello]], 'end_turn'],
      [reads, updates.map { |update| summary(update) }, response.stop_reason]
    )
  end

  it 'answers extension requests in both directions' do
    handles = Thread::Queue.new
    start_agent(
      capabilities: ACP::Types::AgentCapabilities.new,
      extension_requests: { '_myapp/double' => ->(params) { { 'doubled' => params.fetch('n') * 2 } } }
    ) { |client| handles << client }
    connection = start_client(extension_requests: { '_myapp/ping' => ->(params) { { 'echo' => params.fetch('n') } } })
    doubled = within { connection.ext_request('_myapp/double', { 'n' => 21 }) }
    echoed = within { handles.pop.ext_request('_myapp/ping', { 'n' => 'hello' }) }

    assert_equal([{ 'doubled' => 42 }, { 'echo' => 'hello' }], [doubled, echoed])
  end

  it "hands the agent's completion of a url elicitation it served to the complete_elicitation handler" do
    handles = Thread::Queue.new
    start_agent(capabilities: ACP::Types::AgentCapabilities.new) { |client| handles << client }
    completions = Thread::Queue.new
    declined = ACP::Types::CreateElicitationResponse.new(
      action: ACP::Types::CreateElicitationResponse::Action::Decline.new
    )
    completed = ->(notification) { completions << notification }
    connection = start_client(elicitation: ->(_request) { declined }, complete_elicitation: completed)
    within do
      connection.connect(
        ACP::Types::InitializeRequest.new(
          protocol_version: 1,
          client_capabilities: ACP::Types::ClientCapabilities.new(
            elicitation: ACP::Types::ElicitationCapabilities.new(url: ACP::Types::ElicitationUrlCapabilities.new)
          )
        )
      )
    end
    agent = within { handles.pop }
    request = ACP::Types::CreateElicitationRequest.new(
      message: 'Authorize access',
      mode: ACP::Types::CreateElicitationRequest::Mode::Url.new(
        elicitation_id: 'e1',
        url: 'https://example.com/connect',
        scope: ACP::Types::ElicitationSessionScope.new(session_id: 's1')
      )
    )
    answer = within { agent.create_elicitation(request) }
    agent.complete_elicitation(ACP::Types::CompleteElicitationNotification.new(elicitation_id: 'e1'))

    assert_equal([declined.to_h, 'e1'], [answer.to_h, within { completions.pop }.elicitation_id])
  end
end
