# frozen_string_literal: true

require 'test_helper'
require 'acp/types/unstable'

describe ACP::Protocol do
  describe '#mcp_acp_advertised?' do
    it 'reads acp off unstable capabilities' do
      capabilities = ACP::Types::Unstable::AgentCapabilities.new(
        mcp_capabilities: ACP::Types::Unstable::McpCapabilities.new(acp: true)
      )

      assert ACP::Protocol.mcp_acp_advertised?(capabilities)
    end

    it 'is false when the parsed capabilities carry no mcpCapabilities' do
      refute ACP::Protocol.mcp_acp_advertised?(ACP::Types::AgentCapabilities.new)
    end

    it 're-parses a raw capabilities hash' do
      assert ACP::Protocol.mcp_acp_advertised?('mcpCapabilities' => { 'acp' => true })
    end

    it 'is false on a missing or malformed raw capabilities hash' do
      refute ACP::Protocol.mcp_acp_advertised?({})
      refute ACP::Protocol.mcp_acp_advertised?('mcpCapabilities' => { 'acp' => 'yes' })
    end
  end
end
