# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'timeout'
require_relative '../../examples/echo_agent'

describe 'the echo agent behind an agent connection on a stdio transport' do
  before do
    @input, @peer_writer = IO.pipe
    @peer_reader, @output = IO.pipe
    logger = FakeLogger.new
    transport = ACP::Transport::Stdio.new(input: @input, output: @output, logger:)
    connection = ACP::AgentConnection.new(transport:, capabilities: EchoAgent::CAPABILITIES, logger:) do |client|
      EchoAgent.new(client:)
    end
    @reader = connection.start
    @next_id = 0
  end

  after do
    @peer_writer.close
    @reader.join(2)
    [@input, @output, @peer_reader].each(&:close)
  end

  def send_message(message)
    @peer_writer.puts(JSON.generate(message))
  end

  def receive_message
    Timeout.timeout(2) { JSON.parse(@peer_reader.gets) }
  end

  def send_request(method, params)
    @next_id += 1
    send_message({ 'jsonrpc' => '2.0', 'id' => @next_id, 'method' => method, 'params' => params })
  end

  def call(method, params)
    send_request(method, params)
    receive_message
  end

  def update_of(message)
    update = message.dig('params', 'update')
    [message['method'], message.dig('params', 'sessionId'), update['sessionUpdate']]
  end

  it 'replies to session/new before the available commands update' do
    call('initialize', { 'protocolVersion' => 1, 'clientCapabilities' => { 'terminal' => true } })
    reply = call('session/new', { 'cwd' => '/work', 'mcpServers' => [] })
    update = receive_message
    session_id = reply.dig('result', 'sessionId')

    assert_equal(
      [@next_id, ['session/update', session_id, 'available_commands_update']],
      [reply['id'], update_of(update)]
    )
  end

  it 'answers a method the agent does not define with method not found' do
    reply = call('session/set_mode', { 'sessionId' => 's', 'modeId' => 'code' })

    assert_equal ACP::RequestError::METHOD_NOT_FOUND, reply.dig('error', 'code')
  end
end
