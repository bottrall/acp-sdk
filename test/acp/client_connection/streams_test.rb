# frozen_string_literal: true

require 'test_helper'
require 'timeout'

class SenderStub
  attr_reader :requests

  def initialize(response)
    @response = response
    @gate = nil
    @requests = []
  end

  def gate(queue)
    @gate = queue
  end

  def request(method, params = nil)
    @requests << [method, params]
    @gate&.pop
    @response
  end

  def cancellation; end
end

describe ACP::ClientConnection::Streams do
  def within(seconds = 2, &)
    Timeout.timeout(seconds, &)
  end

  def choose(option_id)
    ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id:))
  end

  def permission_request(session_id = 's1')
    {
      'sessionId' => session_id,
      'toolCall' => { 'toolCallId' => 'c1', 'title' => 'Echo' },
      'options' => [{ 'optionId' => 'allow', 'name' => 'Allow', 'kind' => 'allow_once' }]
    }
  end

  def notification(session_id, text)
    {
      'sessionId' => session_id,
      'update' => { 'sessionUpdate' => 'agent_message_chunk', 'content' => { 'type' => 'text', 'text' => text } }
    }
  end

  def blocking_permission(entered, release)
    lambda do |_request|
      entered << true
      release.pop
      choose('allow')
    end
  end

  def streams(
    sender,
    permission: ->(_request) { choose('allow') },
    updates: ->(_notification) {},
    complete_elicitation: nil,
    logger: FakeLogger.new
  )
    ACP::ClientConnection::Streams.new(sender:, permission:, updates:, logger:, complete_elicitation:)
  end

  describe 'stream' do
    it 'sends the request through the sender and returns its reply' do
      sender = SenderStub.new({ 'stopReason' => 'end_turn' })
      engine = streams(sender)
      reply = within { engine.stream('s1', 'session/prompt', { 'prompt' => [] }) { nil } }

      assert_equal [[['session/prompt', { 'prompt' => [] }]], { 'stopReason' => 'end_turn' }], [sender.requests, reply]
    end

    it 'refuses the second call while one is open and yields the first one its updates' do
      sender = SenderStub.new({})
      engine = streams(sender)
      gate = Thread::Queue.new
      sender.gate(gate)
      first_updates = []
      first = Thread.new { engine.stream('s1', 'session/prompt', {}) { |update| first_updates << update } }
      within do
        # The requester thread has to run the request before the session is
        # registered and dispatch can reach its queue.
        sleep(0.001) until sender.requests.any?
        engine.dispatch(notification('s1', 'hello'))
      end
      error = engine.stream('s1', 'session/prompt', {}) { nil }

      assert_equal [-32_600, 'A stream is already open for session s1'], [error.code, error.message]

      gate << true
      within { first.value }

      assert_equal [ACP::Types::SessionUpdate::AgentMessageChunk, 'hello'],
                   [first_updates.first.class, first_updates.first.content.text]
    end

    it 'accepts a new stream for the session once the first one ends' do
      sender = SenderStub.new({})
      engine = streams(sender)
      within { engine.stream('s1', 'session/prompt', {}) { nil } }
      reply = engine.stream('s1', 'session/prompt', {}) { nil }

      assert_equal({}, reply)
    end
  end

  describe 'dispatch' do
    it 'hands a notification with no open stream to the updates handler' do
      notifications = []
      engine = streams(SenderStub.new({}), updates: ->(n) { notifications << n })
      engine.dispatch(notification('s9', 'hello'))

      assert_equal([ACP::Types::SessionUpdate::AgentMessageChunk], notifications.map { |n| n.update.class })
    end

    it 'logs and drops a malformed notification' do
      logger = FakeLogger.new
      engine = streams(SenderStub.new({}), logger:)
      engine.dispatch({ 'update' => { 'sessionUpdate' => 'agent_message_chunk' } })

      assert_equal [:warn, 'dropped malformed session/update: ACP::Types::ParseError: sessionId: is required'],
                   logger.pop
    end
  end

  describe 'request_permission' do
    it 'answers with the handler response' do
      engine = streams(SenderStub.new({}))

      assert_equal 'allow', engine.request_permission(permission_request).outcome.option_id
    end

    it 'answers invalid params when the params do not parse' do
      engine = streams(SenderStub.new({}))
      error = engine.request_permission({})

      assert_equal(-32_602, error.code)
    end
  end

  describe 'cancel' do
    it 'answers a pending permission request with the cancelled outcome' do
      entered = Thread::Queue.new
      release = Thread::Queue.new
      engine = streams(SenderStub.new({}), permission: blocking_permission(entered, release))
      settled = Thread::Queue.new
      Thread.new { settled << engine.request_permission(permission_request) }
      within { entered.pop }
      # Entering the handler proves the request is registered, so the cancel
      # cannot race ahead of it.
      engine.cancel('s1')
      reply = within { settled.pop }

      assert_equal(
        ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Cancelled.new).to_h,
        reply.to_h
      )
    ensure
      release << true
    end

    it 'leaves the queues of other sessions alone' do
      entered = Thread::Queue.new
      release = Thread::Queue.new
      engine = streams(SenderStub.new({}), permission: blocking_permission(entered, release))
      settled = Thread::Queue.new
      Thread.new { settled << engine.request_permission(permission_request('s1')) }
      within { entered.pop }
      engine.cancel('s2')

      assert_empty settled

      release << true

      assert_equal 'allow', within { settled.pop }.outcome.option_id
    ensure
      release << true
    end
  end

  describe 'the elicitation registry' do
    it 'delivers a registered id to the handler and ignores the repeat' do
      completions = []
      engine = streams(SenderStub.new({}), complete_elicitation: ->(n) { completions << n })
      engine.register_elicitation('e1')
      engine.complete_elicitation('elicitationId' => 'e1')
      engine.complete_elicitation('elicitationId' => 'e1')

      assert_equal %w[e1], completions.map(&:elicitation_id)
    end

    it 'ignores an unregistered id' do
      completions = []
      engine = streams(SenderStub.new({}), complete_elicitation: ->(n) { completions << n })
      engine.complete_elicitation('elicitationId' => 'e1')

      assert_equal [], completions
    end
  end
end
