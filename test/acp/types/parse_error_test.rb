# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::ParseError do
  describe '#initialize' do
    it 'composes the message from the rendered path and the detail' do
      error = ACP::Types::ParseError.new(['sessionId'], 'expected String, got Integer')

      assert_equal 'sessionId: expected String, got Integer', error.message
    end

    it 'uses the detail alone when the path is empty' do
      error = ACP::Types::ParseError.new([], 'expected object, got Array')

      assert_equal 'expected object, got Array', error.message
    end
  end

  describe '#path' do
    it 'renders integer segments in brackets' do
      error = ACP::Types::ParseError.new(['prompt', 0], 'is required')

      assert_equal 'prompt[0]', error.path
    end

    it 'renders a leading integer segment in brackets rather than bare' do
      error = ACP::Types::ParseError.new([0, 'text'], 'is required')

      assert_equal '[0].text', error.path
    end

    it 'renders a leading string segment bare' do
      error = ACP::Types::ParseError.new(['sessionId'], 'is required')

      assert_equal 'sessionId', error.path
    end

    it 'renders later string segments behind a dot' do
      error = ACP::Types::ParseError.new(%w[prompt text], 'is required')

      assert_equal 'prompt.text', error.path
    end
  end

  describe '#prefix' do
    it 'returns a new error whose path begins with the given segments' do
      error = ACP::Types::ParseError.new(['audience', 1], 'expected String, got Integer')
      prefixed = error.prefix('annotations')

      assert_equal 'annotations.audience[1]: expected String, got Integer', prefixed.message
      assert_equal ['annotations', 'audience', 1], prefixed.segments
    end

    it 'leaves the original error unchanged' do
      error = ACP::Types::ParseError.new(['audience', 1], 'expected String, got Integer')

      error.prefix('annotations')

      assert_equal 'audience[1]: expected String, got Integer', error.message
      assert_equal ['audience', 1], error.segments
    end
  end
end
