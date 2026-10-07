# frozen_string_literal: true

require 'test_helper'
require 'timeout'

# An agent connection and a client connection wired to each other over pipes,
# so the wire carries the real session/cancel, $/cancel_request and -32800
# messages of the spec's cancellation cascade.
DUMMY_HANDLER = ->(_request) { raise 'not reached' } #: ^(::untyped) -> ::untyped

describe 'request cancellation' do
  before do
    @agent_in, @client_out = IO.pipe
    @client_in, @agent_out = IO.pipe
    @agent_transport = ACP::Transport::Stdio.new(input: @agent_in, output: @agent_out, logger: FakeLogger.new)
    @client_transport = ACP::Transport::Stdio.new(input: @client_in, output: @client_out, logger: FakeLogger.new)
    @readers = []
  end

  after do
    [@client_out, @agent_out].each { |io| io.close unless io.closed? }
    @readers.each { |reader| reader.join(2) }
    [@agent_in, @client_in].each { |io| io.close unless io.closed? }
  end

  def cancelled_on(connection)
    Timeout.timeout(2) { sleep 0.001 until connection.cancelled? }
  end

  # The ask blocks the prompt handler on one outstanding client request: a
  # terminal wait in the first test, a permission in the second.
  def agent_class(_ask)
    Class.new do
      def initialize(client, events, ask)
        @client = client
        @events = events
        @ask = ask
      end

      def new_session(_request)
        ACP::Types::NewSessionResponse.new(session_id: 'sess_1')
      end

      def prompt(request)
        @events << [:prompt, @ask.call(@client, request)]
        ACP::Types::PromptResponse.new(stop_reason: ACP::Types::StopReason::CANCELLED)
      end

      def cancel(_notification)
        @client.cancel_requests
      end
    end
  end

  def start_agent(ask)
    agent = ACP::AgentConnection.new(
      transport: @agent_transport,
      capabilities: ACP::Types::AgentCapabilities.new
    ) { |client| agent_class(ask).new(client, @events, ask) }
    @readers << agent.start
  end

  def start_client(client)
    @readers << client.start
  end

  def client_session(client, terminal_handlers: {})
    capabilities = terminal_handlers.any? ? ACP::Types::ClientCapabilities.new(terminal: true) : nil
    client.connect(ACP::Types::InitializeRequest.new(protocol_version: 1, client_capabilities: capabilities))
    client.session_new(ACP::Types::NewSessionRequest.new(cwd: Dir.pwd, mcp_servers: []))
  end

  def prompt_of(client, session)
    Thread.new do
      client.session_prompt(ACP::Types::PromptRequest.new(session_id: session.session_id, prompt: [text('hi')]))
    end
  end

  def text(text)
    ACP::Types::ContentBlock::Text.new(text:)
  end

  it 'runs the full cascade: session/cancel, $/cancel_request, -32800, stopReason cancelled' do
    @events = Thread::Queue.new
    wait_started = Thread::Queue.new
    saw_cancel = Thread::Queue.new
    connection = nil
    client = ACP::ClientConnection.new(
      transport: @client_transport,
      permission: ->(_request) { raise 'not reached' },
      create_terminal: DUMMY_HANDLER,
      terminal_output: DUMMY_HANDLER,
      kill_terminal: DUMMY_HANDLER,
      release_terminal: DUMMY_HANDLER,
      wait_for_terminal_exit: lambda do |_request|
        wait_started << true
        cancelled_on(connection)
        saw_cancel << true
        ACP::RequestError.request_cancelled
      end
    )
    connection = client
    start_agent(
      lambda do |handle, request|
        handle.wait_for_terminal_exit(
          ACP::Types::WaitForTerminalExitRequest.new(session_id: request.session_id, terminal_id: 't1')
        )
      end
    )
    start_client(client)

    refute_predicate client, :cancelled?
    session = client_session(client, terminal_handlers: { wait_for_terminal_exit: true })

    prompt = prompt_of(client, session)
    wait_started.pop(timeout: 2)

    client.session_cancel(ACP::Types::CancelNotification.new(session_id: session.session_id))

    assert_equal(
      [true, -32_800, 'cancelled'],
      [saw_cancel.pop(timeout: 2), @events.pop(timeout: 2)[1].code, prompt.join(2)&.value&.stop_reason]
    )
  end

  it 'shows a peer-cancelled permission to its handler on its own thread' do
    @events = Thread::Queue.new
    permission_started = Thread::Queue.new
    saw_cancel = Thread::Queue.new
    handles = Thread::Queue.new
    connection = nil
    client = ACP::ClientConnection.new(
      transport: @client_transport,
      permission: lambda do |_request|
        permission_started << true
        cancelled_on(connection)
        saw_cancel << true
        ACP::RequestError.request_cancelled
      end
    )
    connection = client
    ask = lambda do |handle, request|
      handle.request_permission(
        ACP::Types::RequestPermissionRequest.new(
          session_id: request.session_id,
          tool_call: ACP::Types::ToolCallUpdate.new(tool_call_id: 't'),
          options: []
        )
      )
    end
    agent = ACP::AgentConnection.new(
      transport: @agent_transport,
      capabilities: ACP::Types::AgentCapabilities.new
    ) do |handle|
      handles << handle
      agent_class(ask).new(handle, @events, ask)
    end
    @readers << agent.start
    start_client(client)
    session = client_session(client)

    prompt = prompt_of(client, session)
    permission_started.pop(timeout: 2)

    # The agent gives up on its outstanding permission request, as cancel would.
    handles.pop(timeout: 2).cancel_requests

    assert_equal(
      [true, -32_800, 'cancelled'],
      [saw_cancel.pop(timeout: 2), @events.pop(timeout: 2)[1].code, prompt.join(2)&.value&.stop_reason]
    )
  end
end
