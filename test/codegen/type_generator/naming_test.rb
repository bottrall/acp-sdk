# frozen_string_literal: true

require 'test_helper'
require_relative '../../../codegen/type_generator'

describe TypeGenerator::Naming do
  def naming = TypeGenerator::Naming

  describe '.ref_name' do
    it 'strips the $defs pointer prefix' do
      assert_equal 'Step', naming.ref_name('#/$defs/Step')
    end
  end

  describe '.path' do
    it 'maps a constant to its snake-cased path below the types namespace' do
      assert_equal 'unstable/tool_call/in_progress.rb', naming.path('ACP::Types::Unstable::ToolCall::InProgress')
    end
  end

  describe '.snake' do
    it 'snake-cases camel case, splitting after digits and dropping a leading underscore' do
      snaked = %w[mcpServers Http2Stream _meta].map { |name| naming.snake(name) }

      assert_equal %w[mcp_servers http2_stream meta], snaked
    end
  end

  describe '.camel' do
    it 'capitalizes the parts between non-alphanumeric separators' do
      assert_equal(%w[ToolCallUpdate Http2Stream], %w[tool_call_update http2-stream].map { |name| naming.camel(name) })
    end
  end
end
