# frozen_string_literal: true

require 'test_helper'
require 'timeout'

class StreamsFakeSender
  attr_reader :requests, :cancellation

  def initialize(cancellation: nil, &reply)
    @cancellation = cancellation
    @reply = reply || ->(_method, _params) { {} }
    @requests = Thread::Queue.new
  end

  def request(method, params = nil)
    @requests << [method, params]
    @reply.call(method, params)
  end
end

describe ACP::ClientConnection::Streams do
  def within(seconds = 2, &)
    Timeout.timeout(seconds, &)
  end

  def choose(option_id)
    ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id:))
  end

  def cancelled
    ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Cancelled.new)
  end

  def permission_request(session_id = 's1', tool_call_id = 'c1')
    {
      'sessionId' => session_id,
      'toolCall' => { 'toolCallId' => tool_call_id, 'title' => 'Echo' },
      'options' => [{ 'optionId' => 'allow', 'name' => 'Allow', 'kind' => 'allow_once' }]
    }
  end

  def parse_failure_of(params)
    ACP::Types::RequestPermissionRequest.from_h(params)
    nil
  rescue ACP::Types::ParseError => e
    e.message
  end

  def notification(session_id, text)
    {
      'sessionId' => session_id,
      'update' => { 'sessionUpdate' => 'agent_message_chunk', 'content' => { 'type' => 'text', 'text' => text } }
    }
  end

  def held_permission(entered, gates)
    lambda do |request|
      tool_call_id = request.tool_call.tool_call_id
      entered << Thread.current
      gates.fetch(tool_call_id).pop
      choose(tool_call_id)
    end
  end

  def streams(
    sender = StreamsFakeSender.new,
    permission: ->(_request) { choose('allow') },
    updates: ->(_notification) {},
    logger: FakeLogger.new
  )
    ACP::ClientConnection::Streams.new(sender:, permission:, updates:, logger:)
  end

  describe 'stream' do
    it 'refuses a second stream for a session while one is open, without sending it' do
      gate = Thread::Queue.new
      sender = StreamsFakeSender.new do
        gate.pop
        {}
      end
      engine = streams(sender)
      first = Thread.new { engine.stream('s1', 'session/prompt', {}) { nil } }
      within { sender.requests.pop }
      error = engine.stream('s1', 'session/load', {}) { nil }

      assert_equal [ACP::RequestError::INVALID_REQUEST, 'A stream is already open for session s1', 0],
                   [error.code, error.message, sender.requests.size]
    ensure
      gate << true
      first.join
    end

    it 'opens a stream for another session while one is open' do
      gate = Thread::Queue.new
      sender = StreamsFakeSender.new do |method, _params|
        gate.pop if method == 'session/prompt'
        {}
      end
      engine = streams(sender)
      first = Thread.new { engine.stream('s1', 'session/prompt', {}) { nil } }
      within { sender.requests.pop }
      reply = within { engine.stream('s2', 'session/load', {}) { nil } }

      assert_equal({}, reply)
    ensure
      gate << true
      first.join
    end

    it 'sends the request through the sender and returns its reply' do
      sender = StreamsFakeSender.new { { 'stopReason' => 'end_turn' } }
      reply = within { streams(sender).stream('s1', 'session/prompt', { 'prompt' => [] }) { nil } }

      assert_equal [['session/prompt', { 'prompt' => [] }], { 'stopReason' => 'end_turn' }],
                   [sender.requests.pop, reply]
    end

    it 'yields an update as it arrives, before the request settles' do
      gate = Thread::Queue.new
      sender = StreamsFakeSender.new do
        gate.pop
        {}
      end
      engine = streams(sender)
      yielded = Thread::Queue.new
      first = Thread.new { engine.stream('s1', 'session/prompt', {}) { |update| yielded << update } }
      within { sender.requests.pop }
      engine.dispatch(notification('s1', 'hello'))
      update = within { yielded.pop }

      assert_equal [true, 'hello'], [first.alive?, update.content.text]
    ensure
      gate << true
      first.join
    end

    it 'yields every update of the turn in arrival order' do
      gate = Thread::Queue.new
      sender = StreamsFakeSender.new do
        gate.pop
        {}
      end
      engine = streams(sender)
      yielded = []
      first = Thread.new { engine.stream('s1', 'session/prompt', {}) { |update| yielded << update } }
      within { sender.requests.pop }
      %w[one two].each { |text| engine.dispatch(notification('s1', text)) }
      gate << true
      within { first.value }

      assert_equal(%w[one two], yielded.map { |update| update.content.text })
    ensure
      gate << true
    end

    it 'frees the session once the request settles' do
      engine = streams
      within { engine.stream('s1', 'session/prompt', {}) { nil } }
      reply = within { engine.stream('s1', 'session/prompt', {}) { nil } }

      assert_equal({}, reply)
    end

    it 'raises what the sender raises and frees the session' do
      sender = StreamsFakeSender.new do
        Thread.current.report_on_exception = false
        raise IOError, 'closed'
      end
      engine = streams(sender)

      assert_raises(IOError) { within { engine.stream('s1', 'session/prompt', {}) { nil } } }
      # A session still held would return the already-open error instead.
      assert_raises(IOError) { within { engine.stream('s1', 'session/prompt', {}) { nil } } }
    end
  end

  describe 'dispatch' do
    it 'logs and drops a malformed notification' do
      logger = FakeLogger.new
      handled = []
      engine = streams(updates: ->(n) { handled << n }, logger:)
      engine.dispatch({})
      level, message = logger.pop

      assert_equal [:warn, true, []], [level, message.start_with?('dropped malformed session/update: '), handled]
    end

    it 'pushes an update for a session with an open stream to that stream, not to the updates handler' do
      gate = Thread::Queue.new
      sender = StreamsFakeSender.new do
        gate.pop
        {}
      end
      handled = []
      engine = streams(sender, updates: ->(n) { handled << n })
      yielded = []
      first = Thread.new { engine.stream('s1', 'session/prompt', {}) { |update| yielded << update } }
      within { sender.requests.pop }
      engine.dispatch(notification('s1', 'hello'))
      gate << true
      within { first.value }

      assert_equal [%w[hello], []], [yielded.map { |update| update.content.text }, handled]
    ensure
      gate << true
    end

    it 'hands a notification for a session with no open stream to the updates handler' do
      gate = Thread::Queue.new
      sender = StreamsFakeSender.new do
        gate.pop
        {}
      end
      handled = []
      engine = streams(sender, updates: ->(n) { handled << n })
      yielded = []
      first = Thread.new { engine.stream('s1', 'session/prompt', {}) { |update| yielded << update } }
      within { sender.requests.pop }
      engine.dispatch(notification('s9', 'hello'))
      gate << true
      within { first.value }

      assert_equal [[], [%w[s9 hello]]], [yielded, handled.map { |n| [n.session_id, n.update.content.text] }]
    ensure
      gate << true
    end
  end

  describe 'request_permission' do
    it 'answers invalid params carrying the parse failure when a field does not parse' do
      handled = []
      engine = streams(permission: ->(request) { handled << request })
      error = engine.request_permission({})

      assert_equal [ACP::RequestError.invalid_params([parse_failure_of({})]).to_h, []], [error.to_h, handled]
    end

    it "carries the sender's serving cancellation onto the handler's own thread" do
      serving = ACP::Transport::Cancellation.new
      seen = []
      engine = streams(
        StreamsFakeSender.new(cancellation: serving),
        permission: lambda do |_request|
          seen << [Thread.current, ACP::Transport::Cancellation.current]
          choose('allow')
        end
      )
      within { engine.request_permission(permission_request) }
      thread, carried = seen.first

      refute_same Thread.current, thread
      assert_same serving, carried
    end

    it 'calls the handler with the parsed request and answers with what it returns' do
      answer = choose('allow')
      handled = []
      engine = streams(
        permission: lambda do |request|
          handled << request
          answer
        end
      )
      reply = within { engine.request_permission(permission_request('s1', 'c7')) }

      assert_same answer, reply
      assert_equal([%w[s1 c7]], handled.map { |request| [request.session_id, request.tool_call.tool_call_id] })
    end

    it "re-raises the handler's error to its caller" do
      failure = RuntimeError.new('handler failed')
      engine = streams(permission: ->(_request) { raise failure })
      raised = assert_raises(RuntimeError) { within { engine.request_permission(permission_request) } }

      assert_same failure, raised
    end

    it 'answers with an ACP::RequestError the handler returns rather than raising it' do
      refusal = ACP::RequestError.internal_error
      engine = streams(permission: ->(_request) { refusal })

      reply = within { engine.request_permission(permission_request) }

      assert_same refusal, reply
    end
  end

  describe 'cancel' do
    it 'answers a pending permission request with the cancelled outcome and lets its handler finish' do
      entered = Thread::Queue.new
      gates = { 'c1' => Thread::Queue.new }
      engine = streams(permission: held_permission(entered, gates))
      asking = Thread.new { engine.request_permission(permission_request) }
      handler = within { entered.pop }
      engine.cancel('s1')
      reply = within { asking.value }
      gates['c1'] << true

      assert_equal cancelled.to_h, reply.to_h
      assert_same handler, handler.join(2)
    ensure
      gates['c1'] << true
    end

    it 'answers every pending permission request of the session' do
      entered = Thread::Queue.new
      gates = { 'c1' => Thread::Queue.new, 'c2' => Thread::Queue.new }
      engine = streams(permission: held_permission(entered, gates))
      asking = gates.keys.map { |id| Thread.new { engine.request_permission(permission_request('s1', id)) } }
      within { asking.each { entered.pop } }
      engine.cancel('s1')
      replies = within { asking.map { |thread| thread.value.to_h } }

      assert_equal [cancelled.to_h, cancelled.to_h], replies
    ensure
      gates.each_value { |gate| gate << true }
    end

    it 'still answers a pending request after another of the session was answered by its handler' do
      entered = Thread::Queue.new
      gates = { 'c1' => Thread::Queue.new, 'c2' => Thread::Queue.new }
      engine = streams(permission: held_permission(entered, gates))
      first = Thread.new { engine.request_permission(permission_request('s1', 'c1')) }
      first_handler = within { entered.pop }
      second = Thread.new { engine.request_permission(permission_request('s1', 'c2')) }
      within { entered.pop }
      gates['c1'] << true
      # Joining the handler thread waits for it to unregister its request.
      first_reply = within { first_handler.join && first.value }
      engine.cancel('s1')

      assert_equal ['c1', cancelled.to_h], [first_reply.outcome.option_id, within { second.value }.to_h]
    ensure
      gates.each_value { |gate| gate << true }
    end

    it 'leaves the pending requests of other sessions to their handlers' do
      entered = Thread::Queue.new
      gates = { 'c1' => Thread::Queue.new }
      engine = streams(permission: held_permission(entered, gates))
      asking = Thread.new { engine.request_permission(permission_request('s1')) }
      within { entered.pop }
      engine.cancel('s2')
      gates['c1'] << true

      assert_equal choose('c1').to_h, within { asking.value }.to_h
    ensure
      gates['c1'] << true
    end
  end
end
