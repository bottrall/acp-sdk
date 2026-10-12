# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::ParseError do
  it 'names the failing path and the reason' do
    error = ACP::Types::ParseError.new(['sessionId'], 'expected String, got Integer')

    assert_equal ['sessionId: expected String, got Integer', 'sessionId'], [error.message, error.path]
  end

  it 'renders array indexes in brackets and nested keys behind dots' do
    error = ACP::Types::ParseError.new(['prompt', 0, 'text'], 'expected String, got Integer')

    assert_equal 'prompt[0].text: expected String, got Integer', error.message
  end

  it 'prepends container segments without losing the original path' do
    error = ACP::Types::ParseError.new(['audience', 1], 'expected String, got Integer').prefix('annotations')

    assert_equal 'annotations.audience[1]: expected String, got Integer', error.message
  end
end
