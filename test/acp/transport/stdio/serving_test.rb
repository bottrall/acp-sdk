# frozen_string_literal: true

require 'test_helper'

describe ACP::Transport::Stdio::Serving do
  it 'is a frozen pair of the request id and its cancellation' do
    cancellation = ACP::Transport::Cancellation.new

    serving = ACP::Transport::Stdio::Serving.new(id: 7, cancellation:)

    assert_equal [7, cancellation, true], [serving.id, serving.cancellation, serving.frozen?]
  end
end
