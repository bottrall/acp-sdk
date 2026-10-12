# frozen_string_literal: true

require 'test_helper'

describe ACP::Transport::Reply do
  it 'is a frozen pair of the result and the after hook' do
    result = { 'echo' => 'sent' }
    after = -> {}

    reply = ACP::Transport::Reply.new(result, after:)

    assert_equal [result, after, true], [reply.result, reply.after, reply.frozen?]
  end
end
