# frozen_string_literal: true

require 'test_helper'
require 'open3'

require 'acp/types/unstable'

describe ACP::Types do
  describe '.unstable_enabled?' do
    it 'is false until the caller requires the unstable types' do
      out, _err = Open3.capture3(
        'bundle', 'exec', 'ruby', '-I', 'lib', '-e', "require 'acp/sdk'; print ACP::Types.unstable_enabled?"
      )

      assert_equal 'false', out
    end

    it 'is true once the unstable types are required' do
      assert_predicate ACP::Types, :unstable_enabled?
    end
  end

  describe '.parse' do
    it 'rejects a payload that is not an object, even for a type whose keys are all optional' do
      errors = ['garbage', nil, [1]].map { |payload| ACP::Types.parse(ACP::Types::LogoutRequest, payload).message }

      assert_equal ['expected object, got String', 'expected object, got null', 'expected object, got Array'], errors
    end

    it 'returns the error of a payload that does not parse' do
      error = ACP::Types.parse(ACP::Types::CancelNotification, {})

      assert_equal ['sessionId: is required', ['sessionId']], [error.message, error.segments]
    end

    it 'returns the parsed value' do
      parsed = ACP::Types.parse(ACP::Types::CancelNotification, { 'sessionId' => 's1' })

      assert_equal [ACP::Types::CancelNotification, 's1'], [parsed.class, parsed.session_id]
    end
  end
end
