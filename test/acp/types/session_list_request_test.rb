# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::SessionListRequest do
  let(:payload) { { 'cwd' => '/home/user/project', 'cursor' => 'eyJwYWdlIjogMn0=' } }

  it 'is the schema ListSessionsRequest' do
    assert_same ACP::Types::ListSessionsRequest, ACP::Types::SessionListRequest
  end

  it 'round-trips the session/list example from the protocol docs' do
    assert_equal payload, ACP::Types::SessionListRequest.from_h(payload).to_h
  end

  it 'omits absent optional fields' do
    assert_empty ACP::Types::SessionListRequest.from_h({}).to_h
  end
end
