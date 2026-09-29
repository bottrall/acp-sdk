# frozen_string_literal: true

require 'test_helper'

describe ACP::Transport::Handler do
  it 'raises until a subclass implements #call' do
    assert_raises(NotImplementedError) { ACP::Transport::Handler.new.call({}) }
  end
end
