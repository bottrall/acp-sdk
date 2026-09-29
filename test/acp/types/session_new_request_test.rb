# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::SessionNewRequest do
  let(:payload) do
    {
      'cwd' => '/home/user/project',
      'mcpServers' => [
        {
          'name' => 'filesystem',
          'command' => '/path/to/mcp-server',
          'args' => ['--stdio'],
          'env' => [{ 'name' => 'API_KEY', 'value' => 'secret123' }]
        },
        {
          'type' => 'http',
          'name' => 'api-server',
          'url' => 'https://api.example.com/mcp',
          'headers' => [{ 'name' => 'Authorization', 'value' => 'Bearer token123' }]
        },
        {
          'type' => 'sse',
          'name' => 'event-stream',
          'url' => 'https://events.example.com/mcp',
          'headers' => [{ 'name' => 'X-API-Key', 'value' => 'apikey456' }]
        }
      ]
    }
  end

  it 'is the schema NewSessionRequest' do
    assert_same ACP::Types::NewSessionRequest, ACP::Types::SessionNewRequest
  end

  it 'round-trips stdio, http and sse MCP servers' do
    assert_equal payload, ACP::Types::SessionNewRequest.from_h(payload).to_h
  end

  it 'dispatches each MCP server on its transport type' do
    servers = ACP::Types::SessionNewRequest.from_h(payload).mcp_servers.map(&:class)

    assert_equal [ACP::Types::McpServerStdio, ACP::Types::McpServer::Http, ACP::Types::McpServer::Sse], servers
  end
end
