# frozen_string_literal: true

require 'test_helper'
require 'timeout'

class CancellationCascadeAgent
  def initialize(client, ask)
    @client = client
    @ask = ask
  end

  def new_session(_request)
    ACP::Types::NewSessionResponse.new(session_id: 'sess_1')
  end

  def prompt(request)
    outcome = @ask.call(@client, request)
    cancelled = outcome.is_a?(ACP::RequestError) && outcome.code == ACP::RequestError::REQUEST_CANCELLED
    stop_reason = cancelled ? ACP::Types::StopReason::CANCELLED : ACP::Types::StopReason::END_TURN
    ACP::Types::PromptResponse.new(stop_reason:)
  end

  def cancel(_notification)
    @client.cancel_requests
  end
end

describe 'cancellation between a client connection and an agent connection over stdio transports' do
  before do
    @agent_in, @client_out = IO.pipe
    @client_in, @agent_out = IO.pipe
    @agent_transport = ACP::Transport::Stdio.new(input: @agent_in, output: @agent_out, logger: FakeLogger.new)
    @client_transport = ACP::Transport::Stdio.new(input: @client_in, output: @client_out, logger: FakeLogger.new)
    @started = Thread::Queue.new
    @saw_cancel = Thread::Queue.new
    @readers = []
  end

  after do
    [@client_out, @agent_out].each { |io| io.close unless io.closed? }
    @readers.each { |reader| reader.join(2) }
    [@agent_in, @client_in].each { |io| io.close unless io.closed? }
  end

  def start_agent(ask)
    agent = ACP::AgentConnection.new(
      transport: @agent_transport,
      capabilities: ACP::Types::AgentCapabilities.new,
      logger: FakeLogger.new
    ) do |agent_client|
      CancellationCascadeAgent.new(agent_client, ask)
    end
    @readers << agent.start
  end

  def start_client(**handlers)
    @client = ACP::ClientConnection.new(transport: @client_transport, logger: FakeLogger.new, **handlers)
    @readers << @client.start
  end

  def until_cancelled
    lambda do |_request|
      @started << true
      Timeout.timeout(2) { sleep 0.001 until @client.cancelled? }
      @saw_cancel << true
      ACP::RequestError.request_cancelled
    end
  end

  def unreached
    ->(_request) { raise 'not reached' }
  end

  def open_session(client_capabilities: nil)
    @client.connect(ACP::Types::InitializeRequest.new(protocol_version: 1, client_capabilities:))
    @client.new_session(ACP::Types::NewSessionRequest.new(cwd: Dir.pwd, mcp_servers: [])).session_id
  end

  def prompt(session_id)
    content = ACP::Types::ContentBlock::Text.new(text: 'hi')
    Thread.new { @client.prompt_session(ACP::Types::PromptRequest.new(session_id:, prompt: [content])) }
  end

  it "cascades the client's session/cancel through the agent's $/cancel_request to a cancelled stop reason" do
    start_agent(
      lambda do |agent_client, request|
        agent_client.wait_for_terminal_exit(
          ACP::Types::WaitForTerminalExitRequest.new(session_id: request.session_id, terminal_id: 't1')
        )
      end
    )
    start_client(
      permission: unreached,
      create_terminal: unreached,
      terminal_output: unreached,
      kill_terminal: unreached,
      release_terminal: unreached,
      wait_for_terminal_exit: until_cancelled
    )
    session_id = open_session(client_capabilities: ACP::Types::ClientCapabilities.new(terminal: true))
    turn = prompt(session_id)
    @started.pop(timeout: 2)

    @client.cancel_session(ACP::Types::CancelNotification.new(session_id:))

    assert_equal [true, 'cancelled'], [@saw_cancel.pop(timeout: 2), turn.join(2)&.value&.stop_reason]
  end
end
