# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'timeout'

describe ACP::Transport::Stdio do
  before do
    @input, @peer_writer = IO.pipe
    @peer_reader, @output = IO.pipe
    @transport = ACP::Transport::Stdio.new(input: @input, output: @output)
  end

  after do
    @peer_writer.close unless @peer_writer.closed?
    @reader&.join(2)
    [@input, @output, @peer_reader].each(&:close)
  end

  def start(**handlers)
    @reader = @transport.start(**handlers)
  end

  def send_message(message)
    @peer_writer.puts(JSON.generate(message))
  end

  def receive_message
    Timeout.timeout(2) { JSON.parse(@peer_reader.gets) }
  end

  def outcome(thread)
    result = thread.join(2)&.value
    result.ok? ? [:ok, result.value] : [:error, result.error.to_h]
  end

  it 'correlates responses to outbound requests by id' do
    start
    first = Thread.new { @transport.request('fs/read_text_file', { 'path' => 'a.txt' }) }
    first_id = receive_message.fetch('id')
    second = Thread.new { @transport.request('fs/read_text_file', { 'path' => 'b.txt' }) }
    second_id = receive_message.fetch('id')
    send_message({ 'jsonrpc' => '2.0', 'id' => second_id, 'result' => { 'content' => 'B' } })
    send_message({ 'jsonrpc' => '2.0', 'id' => first_id, 'result' => { 'content' => 'A' } })

    assert_equal [[:ok, { 'content' => 'A' }], [:ok, { 'content' => 'B' }]], [outcome(first), outcome(second)]
  end

  it 'returns an error response to an outbound request as an error result' do
    start
    pending = Thread.new { @transport.request('fs/read_text_file', { 'path' => 'missing.txt' }) }
    id = receive_message.fetch('id')
    error = { 'code' => -32_002, 'message' => 'Resource not found', 'data' => { 'path' => 'missing.txt' } }
    send_message({ 'jsonrpc' => '2.0', 'id' => id, 'error' => error })

    assert_equal [:error, error], outcome(pending)
  end

  it 'serves an inbound request with its handler' do
    start(requests: { 'echo' => ->(params) { ACP::Transport::Result.ok(params) } })
    send_message({ 'jsonrpc' => '2.0', 'id' => 7, 'method' => 'echo', 'params' => { 'text' => 'hi' } })

    assert_equal({ 'jsonrpc' => '2.0', 'id' => 7, 'result' => { 'text' => 'hi' } }, receive_message)
  end

  it 'runs a reply\'s after callback once the reply is written' do
    after = -> { @transport.notify('session/update', { 'after' => true }) }
    start(requests: { 'echo' => ->(params) { ACP::Transport::Reply.new(ACP::Transport::Result.ok(params), after:) } })
    send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'echo', 'params' => 'hi' })

    assert_equal(
      [
        { 'jsonrpc' => '2.0', 'id' => 1, 'result' => 'hi' },
        { 'jsonrpc' => '2.0', 'method' => 'session/update', 'params' => { 'after' => true } }
      ],
      [receive_message, receive_message]
    )
  end

  it 'keeps serving after a reply\'s after callback raises' do
    requests = {
      'boom' => ->(_) { ACP::Transport::Reply.new(ACP::Transport::Result.ok('sent'), after: -> { raise 'kaboom' }) },
      'echo' => ->(params) { ACP::Transport::Result.ok(params) }
    }
    start(requests:)
    send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'boom' })
    send_message({ 'jsonrpc' => '2.0', 'id' => 2, 'method' => 'echo', 'params' => 'still here' })

    assert_equal(
      [
        { 'jsonrpc' => '2.0', 'id' => 1, 'result' => 'sent' },
        { 'jsonrpc' => '2.0', 'id' => 2, 'result' => 'still here' }
      ],
      [receive_message, receive_message].sort_by { |message| message['id'] }
    )
  end

  it 'answers an inbound request for an unknown method with method not found' do
    start
    send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'nope' })

    assert_equal(
      { 'jsonrpc' => '2.0', 'id' => 1, 'error' => { 'code' => -32_601, 'message' => 'Method not found' } },
      receive_message
    )
  end

  it 'answers an inbound request whose handler raises with an internal error' do
    start(requests: { 'boom' => ->(_) { raise 'kaboom' } })
    send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'boom' })

    assert_equal(
      { 'jsonrpc' => '2.0', 'id' => 1, 'error' => { 'code' => -32_603, 'message' => 'kaboom' } },
      receive_message
    )
  end

  it 'delivers an inbound notification to its handler' do
    seen = Thread::Queue.new
    start(notifications: { 'session/cancel' => ->(params) { seen << params } })
    send_message({ 'jsonrpc' => '2.0', 'method' => 'session/cancel', 'params' => { 'sessionId' => 'sess_1' } })

    assert_equal({ 'sessionId' => 'sess_1' }, seen.pop(timeout: 2))
  end

  it 'sends an outbound notification without an id' do
    start
    @transport.notify('session/update', { 'sessionId' => 'sess_1' })
    expected = { 'jsonrpc' => '2.0', 'method' => 'session/update', 'params' => { 'sessionId' => 'sess_1' } }

    assert_equal expected, receive_message
  end

  it 'dispatches inbound messages while a handler waits on its own outbound request' do
    session = { 'sessionId' => 'sess_1' }
    cancels = Thread::Queue.new
    prompt = lambda do |params|
      permission = @transport.request('session/request_permission', params).value
      ACP::Transport::Result.ok({ 'permission' => permission, 'cancelled' => cancels.pop(timeout: 2) })
    end
    start(requests: { 'session/prompt' => prompt }, notifications: { 'session/cancel' => cancels.method(:push) })

    send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'session/prompt', 'params' => session })
    permission_id = receive_message.fetch('id')
    send_message({ 'jsonrpc' => '2.0', 'method' => 'session/cancel', 'params' => session })
    send_message({ 'jsonrpc' => '2.0', 'id' => permission_id, 'result' => { 'outcome' => 'cancelled' } })

    assert_equal(
      {
        'jsonrpc' => '2.0',
        'id' => 1,
        'result' => { 'permission' => { 'outcome' => 'cancelled' }, 'cancelled' => { 'sessionId' => 'sess_1' } }
      },
      receive_message
    )
  end

  it 'answers a malformed line with a parse error and keeps reading' do
    start(requests: { 'echo' => ->(params) { ACP::Transport::Result.ok(params) } })
    @peer_writer.puts('{"jsonrpc": "2.0", "id": 1, "method"')
    send_message({ 'jsonrpc' => '2.0', 'id' => 2, 'method' => 'echo', 'params' => 'still here' })

    assert_equal(
      [
        { 'jsonrpc' => '2.0', 'id' => nil, 'error' => { 'code' => -32_700, 'message' => 'Parse error' } },
        { 'jsonrpc' => '2.0', 'id' => 2, 'result' => 'still here' }
      ],
      [receive_message, receive_message]
    )
  end

  it 'answers a line of invalid UTF-8 with a parse error and keeps reading' do
    start(requests: { 'echo' => ->(params) { ACP::Transport::Result.ok(params) } })
    @peer_writer.puts("{\"jsonrpc\": \"2.0\", \"method\": \"\xFF\"}")
    send_message({ 'jsonrpc' => '2.0', 'id' => 2, 'method' => 'echo', 'params' => 'still here' })

    assert_equal(
      [
        { 'jsonrpc' => '2.0', 'id' => nil, 'error' => { 'code' => -32_700, 'message' => 'Parse error' } },
        { 'jsonrpc' => '2.0', 'id' => 2, 'result' => 'still here' }
      ],
      [receive_message, receive_message]
    )
  end

  it 'answers a message that is not a JSON-RPC object with an invalid request error' do
    start
    @peer_writer.puts('[1, 2]')

    assert_equal(
      { 'jsonrpc' => '2.0', 'id' => nil, 'error' => { 'code' => -32_600, 'message' => 'Invalid request' } },
      receive_message
    )
  end

  it 'releases a pending outbound request with an error at EOF' do
    start
    pending = Thread.new { @transport.request('session/request_permission') }
    receive_message
    @peer_writer.close

    assert_equal [:error, { 'code' => -32_603, 'message' => 'Connection closed' }], outcome(pending)
  end

  it 'ends the reader thread at EOF and refuses later requests' do
    start
    @peer_writer.close

    closed = ACP::Transport::Stdio::CONNECTION_CLOSED

    assert_equal [@reader, closed], [@reader.join(2), @transport.request('session/request_permission').error]
  end
end
