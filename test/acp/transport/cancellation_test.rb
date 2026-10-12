# frozen_string_literal: true

require 'test_helper'

describe ACP::Transport::Cancellation do
  after { ACP::Transport::Cancellation.current = nil }

  describe '.current' do
    it 'is nil on a thread that never set one' do
      assert_nil Thread.new { ACP::Transport::Cancellation.current }.value
    end

    it 'returns the cancellation set on the current thread' do
      cancellation = ACP::Transport::Cancellation.new
      ACP::Transport::Cancellation.current = cancellation

      assert_same cancellation, ACP::Transport::Cancellation.current
    end

    it 'does not expose the cancellation set on the current thread to other threads' do
      cancellation = ACP::Transport::Cancellation.new
      ACP::Transport::Cancellation.current = cancellation

      assert_nil Thread.new { ACP::Transport::Cancellation.current }.value
    end
  end

  describe '.current=' do
    it 'clears the current cancellation when given nil' do
      ACP::Transport::Cancellation.current = ACP::Transport::Cancellation.new
      ACP::Transport::Cancellation.current = nil

      assert_nil ACP::Transport::Cancellation.current
    end
  end

  it 'starts uncancelled and reports once cancelled' do
    cancellation = ACP::Transport::Cancellation.new

    refute_predicate cancellation, :cancelled?
    cancellation.cancel

    assert_predicate cancellation, :cancelled?
  end
end
