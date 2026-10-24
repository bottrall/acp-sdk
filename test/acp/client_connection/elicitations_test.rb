# frozen_string_literal: true

require 'test_helper'

describe ACP::ClientConnection::Elicitations do
  def handler(completions)
    Object.new.tap do |object|
      object.define_singleton_method(:complete_elicitation) { |notification| completions << notification }
    end
  end

  describe '#complete' do
    it 'logs and drops a malformed completion' do
      logger = FakeLogger.new
      completions = []
      elicitations = ACP::ClientConnection::Elicitations.new(handler: handler(completions), logger:)
      elicitations.complete({})
      error = ACP::Types.parse(ACP::Types::CompleteElicitationNotification, {})

      assert_equal(
        [[[:warn, "dropped malformed elicitation/complete: #{error.message}"]], []],
        [logger.drain, completions]
      )
    end

    it 'delivers the completion of a registered id to the handler once' do
      completions = []
      elicitations = ACP::ClientConnection::Elicitations.new(handler: handler(completions), logger: FakeLogger.new)
      elicitations.register('e1')
      2.times { elicitations.complete('elicitationId' => 'e1') }

      assert_equal %w[e1], completions.map(&:elicitation_id)
    end

    it 'ignores the completion of an unregistered id' do
      completions = []
      elicitations = ACP::ClientConnection::Elicitations.new(handler: handler(completions), logger: FakeLogger.new)
      elicitations.register('e1')
      elicitations.complete('elicitationId' => 'e2')

      assert_empty completions
    end

    it 'drops the completion of a registered id when there is no handler' do
      logger = FakeLogger.new
      elicitations = ACP::ClientConnection::Elicitations.new(handler: nil, logger:)
      elicitations.register('e1')
      elicitations.complete('elicitationId' => 'e1')

      assert_empty logger.drain
    end

    it 'drops the completion of a registered id when the handler serves no completions' do
      logger = FakeLogger.new
      elicitations = ACP::ClientConnection::Elicitations.new(handler: Object.new, logger:)
      elicitations.register('e1')
      elicitations.complete('elicitationId' => 'e1')

      assert_empty logger.drain
    end
  end
end
