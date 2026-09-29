# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::SessionPromptRequest do
  let(:payload) do
    {
      'sessionId' => 'sess_abc123def456',
      'prompt' => [
        { 'type' => 'text', 'text' => 'Can you analyze this code for potential issues?' },
        {
          'type' => 'resource',
          'resource' => {
            'uri' => 'file:///home/user/project/main.py',
            'mimeType' => 'text/x-python',
            'text' => "def process_data(items):\n    for item in items:\n        print(item)"
          }
        },
        { 'type' => 'image', 'mimeType' => 'image/png', 'data' => 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB...' },
        { 'type' => 'audio', 'mimeType' => 'audio/wav', 'data' => 'UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAAB...' },
        {
          'type' => 'resource_link',
          'uri' => 'file:///home/user/document.pdf',
          'name' => 'document.pdf',
          'mimeType' => 'application/pdf',
          'size' => 1_024_000
        }
      ]
    }
  end

  it 'is the schema PromptRequest' do
    assert_same ACP::Types::PromptRequest, ACP::Types::SessionPromptRequest
  end

  it 'round-trips every content block type' do
    assert_equal payload, ACP::Types::SessionPromptRequest.from_h(payload).to_h
  end

  it 'dispatches each content block on its type' do
    blocks = ACP::Types::SessionPromptRequest.from_h(payload).prompt.map(&:class)

    expected = [
      ACP::Types::ContentBlock::Text,
      ACP::Types::ContentBlock::Resource,
      ACP::Types::ContentBlock::Image,
      ACP::Types::ContentBlock::Audio,
      ACP::Types::ContentBlock::ResourceLink
    ]

    assert_equal expected, blocks
  end
end
