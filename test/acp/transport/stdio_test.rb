# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'timeout'

describe ACP::Transport::Stdio do
  before do
    @input, @peer_writer = IO.pipe
    @peer_reader, @output = IO.pipe
    @logger = FakeLogger.new
    @transport = ACP::Transport::Stdio.new(input: @input, output: @output, logger: @logger)
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

  def value_of(thread)
    thread.join(2)&.value
  end

  def error_reply(id, error)
    { 'jsonrpc' => '2.0', 'id' => id, 'error' => JSON.parse(JSON.generate(error.to_h)) }
  end

  def echo
    { 'echo' => ->(params) { params } }
  end

  def echo_request(id)
    { 'jsonrpc' => '2.0', 'id' => id, 'method' => 'echo', 'params' => { 'text' => 'hi' } }
  end

  def echo_reply(id)
    { 'jsonrpc' => '2.0', 'id' => id, 'result' => { 'text' => 'hi' } }
  end

  describe '#initialize' do
    it 'logs to stderr when no logger is given' do
      transport = ACP::Transport::Stdio.new(input: @input, output: @output)
      @peer_reader.close

      assert_output(nil, /write to closed peer/) { transport.notify('session/update') }
    end
  end

  describe '#start' do
    it 'skips blank lines' do
      start(requests: echo)
      @peer_writer.puts('')
      @peer_writer.puts("  \t ")
      send_message(echo_request(1))

      assert_equal echo_reply(1), receive_message
    end

    it 'ends the reader thread at EOF' do
      start
      @peer_writer.close

      assert_same @reader, @reader.join(2)
    end

    it 'leaves a handler still running at EOF uncancelled, to finish and answer' do
      release = Thread::Queue.new
      wait = ->(_) { release.pop.then { { 'cancelled' => @transport.cancellation.cancelled? } } }
      start(requests: { 'wait' => wait })
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'wait' })
      @peer_writer.close
      @reader.join(2)
      release << true

      assert_equal({ 'jsonrpc' => '2.0', 'id' => 1, 'result' => { 'cancelled' => false } }, receive_message)
    end

    it 'releases a handler blocked on its own outbound request at EOF with connection closed, and it still answers' do
      start(requests: { 'session/prompt' => ->(params) { @transport.request('session/request_permission', params) } })
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'session/prompt' })
      receive_message
      @peer_writer.close

      assert_equal error_reply(1, ACP::Transport::Stdio::CONNECTION_CLOSED), receive_message
    end

    it 'closes the transport when the reader thread dies reading' do
      reader = @transport.start
      reader.report_on_exception = false
      @input.close

      assert_raises(IOError) { reader.join(2) }
      assert_same ACP::RequestError::CONNECTION_CLOSED, @transport.request('session/request_permission')
    end
  end

  describe '#request' do
    it 'refuses a request on a closed transport without writing it' do
      start
      @peer_writer.close
      @reader.join(2)
      refused = @transport.request('session/request_permission')
      @output.close

      assert_equal [ACP::RequestError::CONNECTION_CLOSED, nil], [refused, @peer_reader.gets]
    end

    it 'writes the request with a fresh id, its method and its params' do
      start
      2.times { Thread.new { @transport.request('fs/read_text_file', { 'path' => 'a.txt' }) } }
      request = { 'jsonrpc' => '2.0', 'method' => 'fs/read_text_file', 'params' => { 'path' => 'a.txt' } }

      assert_equal(
        [request.merge('id' => 1), request.merge('id' => 2)],
        [receive_message, receive_message].sort_by { |message| message['id'] }
      )
    end

    it 'omits params when there are none' do
      start
      Thread.new { @transport.request('session/request_permission') }

      assert_equal({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'session/request_permission' }, receive_message)
    end

    it 'returns the result answered for its own id' do
      start
      first = Thread.new { @transport.request('fs/read_text_file', { 'path' => 'a.txt' }) }
      first_id = receive_message.fetch('id')
      second = Thread.new { @transport.request('fs/read_text_file', { 'path' => 'b.txt' }) }
      second_id = receive_message.fetch('id')
      send_message({ 'jsonrpc' => '2.0', 'id' => second_id, 'result' => { 'content' => 'B' } })
      send_message({ 'jsonrpc' => '2.0', 'id' => first_id, 'result' => { 'content' => 'A' } })

      assert_equal [{ 'content' => 'A' }, { 'content' => 'B' }], [value_of(first), value_of(second)]
    end

    [nil, false].each do |result|
      it "returns a #{result.inspect} result instead of connection closed" do
        start
        pending = Thread.new { @transport.request('_vendor/thing') }
        send_message({ 'jsonrpc' => '2.0', 'id' => receive_message.fetch('id'), 'result' => result })

        assert_equal [result], [value_of(pending)]
      end
    end

    it 'returns connection closed when the input ends before the answer' do
      start
      pending = Thread.new { @transport.request('session/request_permission') }
      receive_message
      @peer_writer.close

      assert_same ACP::RequestError::CONNECTION_CLOSED, value_of(pending)
    end
  end

  describe '#notify' do
    it 'writes the notification with its method and params and no id' do
      @transport.notify('session/update', { 'sessionId' => 'sess_1' })
      expected = { 'jsonrpc' => '2.0', 'method' => 'session/update', 'params' => { 'sessionId' => 'sess_1' } }

      assert_equal expected, receive_message
    end

    it 'omits params when there are none' do
      @transport.notify('session/update')

      assert_equal({ 'jsonrpc' => '2.0', 'method' => 'session/update' }, receive_message)
    end
  end

  describe '#cancel' do
    it 'sends $/cancel_request for a pending outbound request and leaves it waiting for the answer' do
      start
      pending = Thread.new { @transport.request('session/request_permission') }
      id = receive_message.fetch('id')
      @transport.cancel(id)

      assert_equal(
        { 'jsonrpc' => '2.0', 'method' => '$/cancel_request', 'params' => { 'requestId' => id } },
        receive_message
      )
      assert_predicate pending, :alive?
      send_message({ 'jsonrpc' => '2.0', 'id' => id, 'result' => { 'outcome' => 'cancelled' } })

      assert_equal({ 'outcome' => 'cancelled' }, value_of(pending))
    end

    it 'sends nothing for an id that is not pending' do
      start
      @transport.cancel(99)
      @transport.notify('session/update')

      assert_equal({ 'jsonrpc' => '2.0', 'method' => 'session/update' }, receive_message)
    end
  end

  describe '#cancel_requests' do
    it 'sends $/cancel_request for every pending outbound request' do
      start
      ids = %w[fs/read_text_file session/request_permission].map do |method|
        Thread.new { @transport.request(method) }
        receive_message.fetch('id')
      end
      @transport.cancel_requests

      assert_equal(
        ids.map { |id| { 'jsonrpc' => '2.0', 'method' => '$/cancel_request', 'params' => { 'requestId' => id } } },
        [receive_message, receive_message].sort_by { |message| message['params'].fetch('requestId') }
      )
    end

    it 'sends nothing for a request that already settled' do
      start
      settled = Thread.new { @transport.request('fs/read_text_file') }
      send_message({ 'jsonrpc' => '2.0', 'id' => receive_message.fetch('id'), 'result' => {} })
      value_of(settled)
      @transport.cancel_requests
      @transport.notify('session/update')

      assert_equal({ 'jsonrpc' => '2.0', 'method' => 'session/update' }, receive_message)
    end
  end

  describe '#cancellation' do
    it 'returns the cancellation current on the calling thread' do
      cancellation = ACP::Transport::Cancellation.new
      seen = Thread.new do
        ACP::Transport::Cancellation.current = cancellation
        @transport.cancellation
      end.value

      assert_same cancellation, seen
    end
  end

  describe 'routing an inbound message' do
    it 'serves a $/cancel_request that carries an id as a request' do
      start
      send_message({ 'jsonrpc' => '2.0', 'id' => 4, 'method' => '$/cancel_request', 'params' => { 'requestId' => 1 } })

      assert_equal error_reply(4, ACP::RequestError.method_not_found('$/cancel_request')), receive_message
    end

    it 'serves a request with the handler for its method, passing its params' do
      start(requests: echo.merge('other' => ->(_) { { 'handler' => 'other' } }))
      send_message(echo_request(7))

      assert_equal echo_reply(7), receive_message
    end

    it 'ignores a notification with no handler' do
      start(requests: echo)
      send_message({ 'jsonrpc' => '2.0', 'method' => 'nope' })
      send_message(echo_request(1))

      assert_equal [echo_reply(1), []], [receive_message, @logger.drain]
    end

    it 'delivers a notification\'s params to the handler for its method' do
      seen = Thread::Queue.new
      start(notifications: { 'session/cancel' => seen.method(:push), 'other' => ->(_) { seen << :other } })
      send_message({ 'jsonrpc' => '2.0', 'method' => 'session/cancel', 'params' => { 'sessionId' => 'sess_1' } })

      assert_equal({ 'sessionId' => 'sess_1' }, seen.pop(timeout: 2))
    end

    it 'runs a notification handler on the reader thread' do
      seen = Thread::Queue.new
      start(notifications: { 'session/update' => ->(_) { seen << Thread.current } })
      send_message({ 'jsonrpc' => '2.0', 'method' => 'session/update' })

      assert_same @reader, seen.pop(timeout: 2)
    end

    it 'logs an error when a notification handler raises and keeps reading' do
      seen = Thread::Queue.new
      start(notifications: { 'boom' => ->(_) { raise 'kaboom' }, 'session/cancel' => seen.method(:push) })
      send_message({ 'jsonrpc' => '2.0', 'method' => 'boom' })
      send_message({ 'jsonrpc' => '2.0', 'method' => 'session/cancel', 'params' => { 'sessionId' => 'sess_1' } })

      assert_equal(
        [{ 'sessionId' => 'sess_1' }, [:error, 'notification handler raised RuntimeError: kaboom']],
        [seen.pop(timeout: 2), @logger.pop]
      )
    end

    it 'ignores a result for an id that is not pending' do
      start(requests: echo)
      send_message({ 'jsonrpc' => '2.0', 'id' => 99, 'result' => {} })
      send_message(echo_request(1))

      assert_equal echo_reply(1), receive_message
    end

    it 'settles an outbound request with the error it is answered with' do
      start
      pending = Thread.new { @transport.request('fs/read_text_file', { 'path' => 'missing.txt' }) }
      error = { 'code' => -32_002, 'message' => 'Resource not found', 'data' => { 'path' => 'missing.txt' } }
      send_message({ 'jsonrpc' => '2.0', 'id' => receive_message.fetch('id'), 'error' => error })
      result = value_of(pending)

      assert_equal(
        [ACP::RequestError, -32_002, 'Resource not found', { 'path' => 'missing.txt' }],
        [result.class, result.code, result.message, result.data]
      )
    end

    it 'answers a message whose method is not a string with invalid request' do
      start
      send_message({ 'jsonrpc' => '2.0', 'id' => 7, 'method' => 5 })

      assert_equal error_reply(7, ACP::RequestError.invalid_request), receive_message
    end

    {
      'an error that is not an object' => { 'error' => 'boom' },
      'an error with a string code' => { 'error' => { 'code' => '-32002', 'message' => 'Resource not found' } },
      'an error with a float code' => { 'error' => { 'code' => -32_002.0, 'message' => 'Resource not found' } },
      'an error with no message' => { 'error' => { 'code' => -32_002 } },
      'a null error' => { 'error' => nil },
      'neither a result nor an error' => {}
    }.each do |fault, members|
      it "settles an outbound request answered with #{fault} as an invalid response, replying nothing" do
        start
        pending = Thread.new { @transport.request('fs/read_text_file') }
        response = { 'jsonrpc' => '2.0', 'id' => receive_message.fetch('id') }.merge(members)
        send_message(response)
        result = value_of(pending)
        @transport.notify('session/update')

        assert_equal ACP::RequestError.invalid_response(response).to_h, result.to_h
        assert_equal({ 'jsonrpc' => '2.0', 'method' => 'session/update' }, receive_message)
      end
    end

    it 'warns and drops a malformed response for an id that is not pending, then keeps reading' do
      start(requests: echo)
      send_message({ 'jsonrpc' => '2.0', 'id' => 99, 'error' => 'boom' })
      send_message(echo_request(1))

      assert_equal(
        [echo_reply(1), [:warn, 'dropped malformed response: no pending request for its id']],
        [receive_message, @logger.pop]
      )
    end

    it 'echoes a string id on an invalid request reply' do
      start
      send_message({ 'jsonrpc' => '2.0', 'id' => 'req-7', 'method' => 5 })

      assert_equal 'req-7', receive_message.fetch('id')
    end

    {
      'no id' => { 'jsonrpc' => '2.0', 'method' => 5 },
      'an id that is not a string or number' => { 'jsonrpc' => '2.0', 'id' => [7], 'method' => 5 }
    }.each do |fault, message|
      it "answers an invalid request with #{fault} with a null id" do
        start
        send_message(message)

        assert_equal error_reply(nil, ACP::RequestError.invalid_request), receive_message
      end
    end
  end

  describe 'parsing an inbound line' do
    it 'answers a line of invalid UTF-8 with a parse error and keeps reading' do
      start(requests: echo)
      @peer_writer.puts("{\"jsonrpc\": \"2.0\", \"method\": \"\xFF\"}")
      send_message(echo_request(2))

      assert_equal(
        [error_reply(nil, ACP::RequestError.parse_error), echo_reply(2)],
        [receive_message, receive_message]
      )
    end

    it 'answers a line that is not JSON with a parse error and keeps reading' do
      start(requests: echo)
      @peer_writer.puts('{"jsonrpc": "2.0", "id": 1, "method"')
      send_message(echo_request(2))

      assert_equal(
        [error_reply(nil, ACP::RequestError.parse_error), echo_reply(2)],
        [receive_message, receive_message]
      )
    end

    it 'answers JSON that is not an object with invalid request' do
      start
      @peer_writer.puts('[1, 2]')

      assert_equal error_reply(nil, ACP::RequestError.invalid_request), receive_message
    end
  end

  describe 'serving an inbound request' do
    it 'gives each handler its own cancellation' do
      seen = Thread::Queue.new
      start(requests: { 'echo' => ->(params) { params.tap { seen << @transport.cancellation } } })
      [1, 2].each { |id| send_message(echo_request(id)) }
      cancellations = [seen.pop(timeout: 2), seen.pop(timeout: 2)]

      assert_equal(
        [[ACP::Transport::Cancellation, ACP::Transport::Cancellation], 2],
        [cancellations.map(&:class), cancellations.uniq.size]
      )
    end

    it 'answers a later request while an earlier handler is still running' do
      release = Thread::Queue.new
      start(requests: echo.merge('block' => ->(_) { release.pop.then { { 'blocked' => 'done' } } }))
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'block' })
      send_message(echo_request(2))
      answered_first = receive_message
      release << true

      assert_equal(
        [echo_reply(2), { 'jsonrpc' => '2.0', 'id' => 1, 'result' => { 'blocked' => 'done' } }],
        [answered_first, receive_message]
      )
    end

    it 'keeps reading while a handler waits on its own outbound request' do
      cancels = Thread::Queue.new
      prompt = lambda do |params|
        permission = @transport.request('session/request_permission', params)
        { 'permission' => permission, 'cancelled' => cancels.pop(timeout: 2) }
      end
      start(requests: { 'session/prompt' => prompt }, notifications: { 'session/cancel' => cancels.method(:push) })
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'session/prompt' })
      permission_id = receive_message.fetch('id')
      send_message({ 'jsonrpc' => '2.0', 'method' => 'session/cancel', 'params' => { 'sessionId' => 'sess_1' } })
      send_message({ 'jsonrpc' => '2.0', 'id' => permission_id, 'result' => { 'outcome' => 'cancelled' } })

      assert_equal(
        { 'permission' => { 'outcome' => 'cancelled' }, 'cancelled' => { 'sessionId' => 'sess_1' } },
        receive_message.fetch('result')
      )
    end

    it 'answers a method with no handler with method not found naming the method' do
      start
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'nope' })

      assert_equal error_reply(1, ACP::RequestError.method_not_found('nope')), receive_message
    end

    it 'answers with a Reply\'s result, then runs its after callback' do
      after = -> { @transport.notify('session/update', { 'after' => true }) }
      start(requests: { 'echo' => ->(params) { ACP::Transport::Reply.new(params, after:) } })
      send_message(echo_request(1))

      assert_equal(
        [echo_reply(1), { 'jsonrpc' => '2.0', 'method' => 'session/update', 'params' => { 'after' => true } }],
        [receive_message, receive_message]
      )
    end

    it 'logs an error when a Reply\'s after callback raises, having already answered' do
      after = -> { raise 'kaboom' }
      start(requests: { 'echo' => ->(params) { ACP::Transport::Reply.new(params, after:) } })
      send_message(echo_request(1))

      assert_equal(
        [echo_reply(1), [:error, 'reply after callback raised RuntimeError: kaboom']],
        [receive_message, @logger.pop]
      )
    end

    it 'answers with the error a handler returns' do
      error = ACP::RequestError.new(code: -32_001, message: 'handler said no', data: { 'why' => 'because' })
      start(requests: { 'refuse' => ->(_) { error } })
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'refuse' })

      assert_equal error_reply(1, error), receive_message
    end

    it 'answers with the to_h of the response a handler returns' do
      response = ACP::Types::NewSessionResponse.new(session_id: 'sess_1')
      start(requests: { 'session/new' => ->(_) { response } })
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'session/new' })

      assert_equal({ 'jsonrpc' => '2.0', 'id' => 1, 'result' => { 'sessionId' => 'sess_1' } }, receive_message)
    end

    it 'stops tracking a request once it is answered, so a later cancel for its id does nothing' do
      seen = Thread::Queue.new
      start(requests: { 'echo' => ->(params) { params.tap { seen << [Thread.current, @transport.cancellation] } } })
      send_message(echo_request(1))
      serving, cancellation = seen.pop(timeout: 2)
      serving.join(2)
      receive_message
      send_message({ 'jsonrpc' => '2.0', 'method' => '$/cancel_request', 'params' => { 'requestId' => 1 } })
      send_message(echo_request(2))
      seen.pop(timeout: 2)

      refute_predicate cancellation, :cancelled?
    end
  end

  describe 'receiving $/cancel_request' do
    {
      'no params' => nil,
      'params that are not an object' => [7],
      'no requestId' => {},
      'a requestId that is not a string or integer' => { 'requestId' => 7.5 }
    }.each do |fault, params|
      it "warns and drops one with #{fault}, then keeps reading" do
        start(requests: echo)
        send_message({ 'jsonrpc' => '2.0', 'method' => '$/cancel_request', 'params' => params }.compact)
        send_message(echo_request(1))

        assert_equal(
          [echo_reply(1), [:warn, 'dropped malformed $/cancel_request: missing requestId']],
          [receive_message, @logger.pop]
        )
      end
    end

    it 'ignores one for an id that is not being served and keeps reading' do
      start(requests: echo)
      send_message({ 'jsonrpc' => '2.0', 'method' => '$/cancel_request', 'params' => { 'requestId' => 99 } })
      send_message(echo_request(1))

      assert_equal [echo_reply(1), []], [receive_message, @logger.drain]
    end

    [7, 'req-7'].each do |id|
      it "cancels the cancellation of the request being served under the #{id.class.name.downcase} id" do
        handler = lambda do |_params|
          Timeout.timeout(2) { sleep(0.001) until @transport.cancellation.cancelled? }
          { 'saw' => 'cancel' }
        end
        start(requests: { 'wait' => handler })
        send_message({ 'jsonrpc' => '2.0', 'id' => id, 'method' => 'wait' })
        send_message({ 'jsonrpc' => '2.0', 'method' => '$/cancel_request', 'params' => { 'requestId' => id } })

        assert_equal({ 'jsonrpc' => '2.0', 'id' => id, 'result' => { 'saw' => 'cancel' } }, receive_message)
      end
    end

    it 'leaves the answer to the handler: a cancelled request is answered once, with the handler\'s outcome' do
      release = Thread::Queue.new
      start(requests: echo.merge('wait' => ->(_) { release.pop.then { { 'wait' => 'done' } } }))
      send_message({ 'jsonrpc' => '2.0', 'id' => 7, 'method' => 'wait' })
      send_message({ 'jsonrpc' => '2.0', 'method' => '$/cancel_request', 'params' => { 'requestId' => 7 } })
      send_message(echo_request(8))
      answered_first = receive_message
      release << true

      assert_equal(
        [echo_reply(8), { 'jsonrpc' => '2.0', 'id' => 7, 'result' => { 'wait' => 'done' } }],
        [answered_first, receive_message]
      )
    end
  end

  describe 'a request handler that raises' do
    it 'is answered with an internal error that carries none of the exception' do
      start(requests: { 'boom' => ->(_) { raise 'secret db password leaked' } })
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'boom' })

      assert_equal error_reply(1, ACP::RequestError.internal_error), receive_message
    end

    it 'logs the exception as an error' do
      start(requests: { 'boom' => ->(_) { raise 'secret db password leaked' } })
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'boom' })

      assert_equal [:error, 'request handler raised RuntimeError: secret db password leaked'], @logger.pop
    end
  end

  describe 'writing to a closed peer' do
    it 'warns instead of raising, for every write' do
      @peer_reader.close
      2.times { @transport.notify('session/update') }
      warning = [:warn, "write to closed peer: Errno::EPIPE: #{Errno::EPIPE.new.message}"]

      assert_equal [warning, warning], @logger.drain
    end

    it 'does not kill the reader thread when its own reply cannot be written' do
      seen = Thread::Queue.new
      start(notifications: { 'session/cancel' => seen.method(:push) })
      @peer_reader.close
      @peer_writer.puts('not json')
      warning = @logger.pop
      send_message({ 'jsonrpc' => '2.0', 'method' => 'session/cancel', 'params' => { 'sessionId' => 'sess_1' } })

      assert_equal(
        [[:warn, "write to closed peer: Errno::EPIPE: #{Errno::EPIPE.new.message}"], { 'sessionId' => 'sess_1' }],
        [warning, seen.pop(timeout: 2)]
      )
    end

    it 'warns and drops the reply of a handler that finishes after EOF once the peer is gone' do
      release = Thread::Queue.new
      start(requests: { 'wait' => ->(_) { release.pop.then { { 'wait' => 'done' } } } })
      send_message({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'wait' })
      @peer_writer.close
      @reader.join(2)
      @peer_reader.close
      release << true

      assert_equal [:warn, "write to closed peer: Errno::EPIPE: #{Errno::EPIPE.new.message}"], @logger.pop
    end
  end
end
