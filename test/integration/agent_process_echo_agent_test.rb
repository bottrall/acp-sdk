# frozen_string_literal: true

require 'test_helper'
require 'rbconfig'
require 'timeout'
require_relative '../../examples/echo_agent'

describe 'an agent process running examples/echo_agent.rb' do
  def allowing
    lambda { |_request|
      ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id: EchoAgent::ALLOW))
    }
  end

  def prompt_turn(connection)
    connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1))
    session = connection.new_session(ACP::Types::NewSessionRequest.new(cwd: Dir.pwd, mcp_servers: []))
    prompt = [ACP::Types::ContentBlock::Text.new(text: 'hello')]
    connection.prompt_session(ACP::Types::PromptRequest.new(session_id: session.session_id, prompt:)) { nil }
  end

  it 'completes a prompt turn' do
    response = ACP::AgentProcess.spawn(RbConfig.ruby, 'examples/echo_agent.rb', permission: allowing) do |connection|
      Timeout.timeout(5) { prompt_turn(connection) }
    end

    assert_equal 'end_turn', response.stop_reason
  end
end
