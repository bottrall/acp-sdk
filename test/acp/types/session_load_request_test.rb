# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::SessionLoadRequest do
  let(:payload) do
    {
      'sessionId' => 'sess_789xyz',
      'cwd' => '/home/user/project',
      'additionalDirectories' => ['/home/user/shared-lib', '/home/user/product-docs'],
      'mcpServers' => [
        { 'name' => 'filesystem', 'command' => '/path/to/mcp-server', 'args' => ['--mode', 'filesystem'], 'env' => [] }
      ]
    }
  end

  it 'is the schema LoadSessionRequest' do
    assert_same ACP::Types::LoadSessionRequest, ACP::Types::SessionLoadRequest
  end

  it 'round-trips the session/load example from the protocol docs' do
    assert_equal payload, ACP::Types::SessionLoadRequest.from_h(payload).to_h
  end
end
