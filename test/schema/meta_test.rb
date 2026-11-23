# frozen_string_literal: true

require 'test_helper'

describe 'schema/meta*.json' do
  it 'lists only sections a coverage test covers' do
    covered = %w[agentMethods clientMethods protocolMethods proxyMethods]

    assert_empty SCHEMA_METHODS.keys - covered, "cover these in the connection tests or in #{__FILE__}"
  end

  it 'lists $/cancel_request, which the transport handles, as the only protocol method' do
    assert_equal [ACP::Transport::Stdio::CANCEL_REQUEST], SCHEMA_METHODS.fetch('protocolMethods')
  end
end
