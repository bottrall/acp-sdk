# frozen_string_literal: true

require 'test_helper'
require 'acp/types/unstable'
require 'open3'

describe ACP::Protocol do
  describe '#advertised?' do
    response_class = Struct.new(:capabilities)
    capabilities_class = Struct.new(:flag)
    path = %i[capabilities flag].freeze

    it 'is true when the path leads to a truthy value' do
      assert_same true, ACP::Protocol.advertised?(response_class.new(capabilities_class.new(Object.new)), path)
    end

    it 'is false when the path leads to nil or false' do
      answers = [nil, false].map do |flag|
        ACP::Protocol.advertised?(response_class.new(capabilities_class.new(flag)), path)
      end

      assert_equal [false, false], answers
    end

    it 'is false when a node along the path lacks the reader' do
      assert_same false, ACP::Protocol.advertised?(response_class.new(Object.new), path)
    end

    it 'is false when a node along the path is nil' do
      assert_same false, ACP::Protocol.advertised?(response_class.new(nil), path)
    end
  end

  describe '#mcp_acp_advertised?' do
    it 'is false when the unstable types are not loaded' do
      out, _err = Open3.capture3('bundle', 'exec', 'ruby', '-I', 'lib', '-e', <<~RUBY)
        require 'acp/sdk'
        print ACP::Protocol.mcp_acp_advertised?('mcpCapabilities' => { 'acp' => true })
      RUBY

      assert_equal 'false', out
    end

    it 'reads acp off typed unstable capabilities' do
      capabilities = ACP::Types::Unstable::AgentCapabilities.new(
        mcp_capabilities: ACP::Types::Unstable::McpCapabilities.new(acp: true)
      )

      assert ACP::Protocol.mcp_acp_advertised?(capabilities)
    end

    it 'is false when the typed capabilities carry no mcp capabilities' do
      refute ACP::Protocol.mcp_acp_advertised?(ACP::Types::Unstable::AgentCapabilities.new)
    end

    it 'is false for stable typed capabilities, whose mcp capabilities are not the unstable type' do
      capabilities = ACP::Types::AgentCapabilities.new(mcp_capabilities: ACP::Types::McpCapabilities.new)

      refute ACP::Protocol.mcp_acp_advertised?(capabilities)
    end

    it 'is false when the typed mcp capabilities do not advertise acp' do
      capabilities = ACP::Types::Unstable::AgentCapabilities.new(
        mcp_capabilities: ACP::Types::Unstable::McpCapabilities.new(acp: false)
      )

      refute ACP::Protocol.mcp_acp_advertised?(capabilities)
    end

    it 're-parses a raw capabilities hash' do
      assert ACP::Protocol.mcp_acp_advertised?('mcpCapabilities' => { 'acp' => true })
    end

    it 'ignores a malformed unrelated capability beside the raw mcpCapabilities' do
      assert ACP::Protocol.mcp_acp_advertised?('mcpCapabilities' => { 'acp' => true }, 'positionEncoding' => 'utf-7')
    end

    it 'is false when the raw capabilities hash carries no mcpCapabilities' do
      refute ACP::Protocol.mcp_acp_advertised?({})
    end

    it 'is false when the raw mcpCapabilities does not advertise acp' do
      refute ACP::Protocol.mcp_acp_advertised?('mcpCapabilities' => {})
      refute ACP::Protocol.mcp_acp_advertised?('mcpCapabilities' => { 'acp' => false })
    end

    it 'is false when the raw mcpCapabilities is not an object' do
      refute ACP::Protocol.mcp_acp_advertised?('mcpCapabilities' => 'nope')
    end

    it 'is false when the raw mcpCapabilities is malformed' do
      refute ACP::Protocol.mcp_acp_advertised?('mcpCapabilities' => { 'acp' => 'yes' })
    end

    it 'is false when the raw capabilities are not a hash' do
      [42, nil].each { |raw| refute ACP::Protocol.mcp_acp_advertised?(raw) }
    end
  end
end
