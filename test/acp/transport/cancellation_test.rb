# frozen_string_literal: true

require 'test_helper'

describe ACP::Transport::Cancellation do
  it 'starts uncancelled and reports once cancelled' do
    cancellation = ACP::Transport::Cancellation.new

    refute_predicate cancellation, :cancelled?
    cancellation.cancel

    assert_predicate cancellation, :cancelled?
  end
end
