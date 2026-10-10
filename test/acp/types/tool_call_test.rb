# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::ToolCall do
  let(:payload) do
    {
      'toolCallId' => 'call_001',
      'title' => 'Reading configuration file',
      'name' => 'read_file'
    }
  end

  # ToolCall is an alias of the SessionUpdate::ToolCall variant class, so the
  # discriminator tag rides along in to_h.
  it 'round-trips the name' do
    assert_equal payload.merge('sessionUpdate' => 'tool_call'), ACP::Types::ToolCall.from_h(payload).to_h
  end

  it 'omits the name when absent' do
    absent = payload.except('name')

    assert_equal absent.merge('sessionUpdate' => 'tool_call'), ACP::Types::ToolCall.from_h(absent).to_h
  end
end

describe ACP::Types::ToolCallUpdate do
  let(:payload) do
    {
      'toolCallId' => 'call_001',
      'name' => 'read_file'
    }
  end

  it 'round-trips the name' do
    assert_equal payload, ACP::Types::ToolCallUpdate.from_h(payload).to_h
  end

  it 'omits the name when absent' do
    absent = payload.except('name')

    assert_equal absent, ACP::Types::ToolCallUpdate.from_h(absent).to_h
  end
end
