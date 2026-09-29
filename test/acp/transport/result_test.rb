# frozen_string_literal: true

require 'test_helper'

describe ACP::Transport::Result do
  it 'is ok with a value and no error' do
    result = ACP::Transport::Result.ok({ 'content' => 'A' })

    assert_equal [true, { 'content' => 'A' }, nil], [result.ok?, result.value, result.error]
  end

  it 'is not ok with an error and no value' do
    error = ACP::Transport::ResponseError.new(code: -32_002, message: 'Resource not found')
    result = ACP::Transport::Result.error(error)

    assert_equal [false, nil, error], [result.ok?, result.value, result.error]
  end
end
