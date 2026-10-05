# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::SessionUpdate do
  examples = {
    ACP::Types::SessionUpdate::UserMessageChunk => {
      'sessionUpdate' => 'user_message_chunk',
      'messageId' => 'msg_user_8f7a1',
      'content' => { 'type' => 'text', 'text' => "What's the capital of France?" }
    },
    ACP::Types::SessionUpdate::AgentMessageChunk => {
      'sessionUpdate' => 'agent_message_chunk',
      'messageId' => 'msg_agent_c42b9',
      'content' => { 'type' => 'text', 'text' => 'The capital of France is Paris.' }
    },
    ACP::Types::SessionUpdate::AgentThoughtChunk => {
      'sessionUpdate' => 'agent_thought_chunk',
      'content' => { 'type' => 'text', 'text' => 'The user is asking about geography.' }
    },
    ACP::Types::SessionUpdate::ToolCall => {
      'sessionUpdate' => 'tool_call',
      'toolCallId' => 'call_001',
      'title' => 'Reading configuration file',
      'name' => 'read_file',
      'kind' => 'read',
      'status' => 'pending',
      'locations' => [{ 'path' => '/home/user/project/src/main.py', 'line' => 42 }],
      'rawInput' => { 'path' => '/home/user/project/src/main.py' }
    },
    ACP::Types::SessionUpdate::ToolCallUpdate => {
      'sessionUpdate' => 'tool_call_update',
      'toolCallId' => 'call_001',
      'name' => 'read_file',
      'status' => 'completed',
      'content' => [
        { 'type' => 'content', 'content' => { 'type' => 'text', 'text' => 'Analysis complete. Found 3 issues.' } },
        {
          'type' => 'diff',
          'path' => '/home/user/project/src/config.json',
          'oldText' => "{\n  \"debug\": false\n}",
          'newText' => "{\n  \"debug\": true\n}"
        },
        { 'type' => 'terminal', 'terminalId' => 'term_xyz789' }
      ]
    },
    ACP::Types::SessionUpdate::Plan => {
      'sessionUpdate' => 'plan',
      'entries' => [
        { 'content' => 'Check for syntax errors', 'priority' => 'high', 'status' => 'pending' },
        { 'content' => 'Suggest improvements', 'priority' => 'low', 'status' => 'pending' }
      ]
    },
    ACP::Types::SessionUpdate::AvailableCommandsUpdate => {
      'sessionUpdate' => 'available_commands_update',
      'availableCommands' => [
        {
          'name' => 'web',
          'description' => 'Search the web for information',
          'input' => { 'hint' => 'query to search for' }
        }
      ]
    },
    ACP::Types::SessionUpdate::CurrentModeUpdate => {
      'sessionUpdate' => 'current_mode_update',
      'currentModeId' => 'code'
    },
    ACP::Types::SessionUpdate::ConfigOptionUpdate => {
      'sessionUpdate' => 'config_option_update',
      'configOptions' => [
        {
          'id' => 'model',
          'name' => 'Model',
          'category' => 'model',
          'type' => 'select',
          'currentValue' => 'model-1',
          'options' => [
            { 'value' => 'model-1', 'name' => 'Model 1', 'description' => 'The fastest model' },
            { 'value' => 'model-2', 'name' => 'Model 2', 'description' => 'The most powerful model' }
          ]
        },
        {
          'id' => 'brave_mode',
          'name' => 'Brave Mode',
          'description' => 'Skip confirmation prompts and act autonomously',
          'type' => 'boolean',
          'currentValue' => true
        }
      ]
    },
    ACP::Types::SessionUpdate::SessionInfoUpdate => {
      'sessionUpdate' => 'session_info_update',
      'title' => 'Implement user authentication',
      '_meta' => { 'tags' => %w[feature auth], 'priority' => 'high' }
    },
    ACP::Types::SessionUpdate::UsageUpdate => {
      'sessionUpdate' => 'usage_update',
      'used' => 53_000,
      'size' => 200_000,
      'cost' => { 'amount' => 0.045, 'currency' => 'USD' }
    }
  }

  examples.each do |variant, payload|
    it "round-trips #{payload.fetch('sessionUpdate')} as #{variant.name.split('::').last}" do
      update = ACP::Types::SessionUpdate.from_h(payload)

      assert_equal [variant, payload], [update.class, update.to_h]
    end
  end

  it 'passes an update type it does not know through as the raw hash' do
    payload = { 'sessionUpdate' => 'future_update', 'detail' => 1 }

    assert_same payload, ACP::Types::SessionUpdate.from_h(payload)
  end

  it 'rejects a tool call update with a status outside the closed enum and names the path' do
    payload = { 'sessionUpdate' => 'tool_call_update', 'toolCallId' => 'call_001', 'status' => 'weird' }

    error = assert_raises(ACP::Types::ParseError) { ACP::Types::SessionUpdate.from_h(payload) }

    assert_equal 'status: expected one of "pending", "in_progress", "completed", "failed", got String', error.message
  end

  it 'round-trips inside a session/update notification' do
    payload = { 'sessionId' => 'sess_abc123def456', 'update' => examples.values.first }

    assert_equal payload, ACP::Types::SessionNotification.from_h(payload).to_h
  end
end
