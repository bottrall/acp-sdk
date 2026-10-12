# frozen_string_literal: true

require 'test_helper'

describe 'generated types' do
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
