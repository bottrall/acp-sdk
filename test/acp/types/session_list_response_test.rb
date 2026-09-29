# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::SessionListResponse do
  let(:payload) do
    {
      'sessions' => [
        {
          'sessionId' => 'sess_abc123def456',
          'cwd' => '/home/user/project',
          'title' => 'Implement session list API',
          'updatedAt' => '2025-10-29T14:22:15Z',
          '_meta' => { 'messageCount' => 12, 'hasErrors' => false }
        },
        {
          'sessionId' => 'sess_uvw345rst678',
          'cwd' => '/home/user/project',
          'updatedAt' => '2025-10-27T15:30:00Z'
        }
      ],
      'nextCursor' => 'eyJwYWdlIjogM30='
    }
  end

  it 'is the schema ListSessionsResponse' do
    assert_same ACP::Types::ListSessionsResponse, ACP::Types::SessionListResponse
  end

  it 'round-trips the session/list example from the protocol docs' do
    assert_equal payload, ACP::Types::SessionListResponse.from_h(payload).to_h
  end

  it 'exposes _meta as meta' do
    assert_equal 12, ACP::Types::SessionListResponse.from_h(payload).sessions.first.meta&.fetch('messageCount')
  end
end
