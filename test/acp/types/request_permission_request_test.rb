# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::RequestPermissionRequest do
  let(:payload) do
    {
      'sessionId' => 'sess_abc123def456',
      'toolCall' => {
        'toolCallId' => 'call_switch_mode_001',
        'title' => 'Ready for implementation',
        'kind' => 'switch_mode',
        'status' => 'pending',
        'content' => [{ 'type' => 'content', 'content' => { 'type' => 'text', 'text' => '## Implementation Plan...' } }]
      },
      'options' => [
        { 'optionId' => 'code', 'name' => 'Yes, and auto-accept all actions', 'kind' => 'allow_always' },
        { 'optionId' => 'ask', 'name' => 'Yes, and manually accept actions', 'kind' => 'allow_once' },
        { 'optionId' => 'reject', 'name' => 'No, stay in architect mode', 'kind' => 'reject_once' }
      ]
    }
  end

  it 'round-trips the session/request_permission example from the protocol docs' do
    assert_equal payload, ACP::Types::RequestPermissionRequest.from_h(payload).to_h
  end

  it 'builds the tool call as a ToolCallUpdate' do
    assert_instance_of ACP::Types::ToolCallUpdate, ACP::Types::RequestPermissionRequest.from_h(payload).tool_call
  end
end
