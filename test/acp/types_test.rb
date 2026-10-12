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

  # Generated types are pinned at the generator (test/codegen); this is the one smoke test.
  it 'round-trips a payload through a generated object, union and alias' do
    payload = {
      'sessionId' => 'sess_abc123def456',
      'update' => { 'sessionUpdate' => 'tool_call', 'toolCallId' => 'call_001', 'title' => 'Reading config' }
    }

    notification = ACP::Types::SessionNotification.from_h(payload)

    assert_equal [ACP::Types::ToolCall, payload], [notification.update.class, notification.to_h]
  end
end
