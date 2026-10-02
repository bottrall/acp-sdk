# frozen_string_literal: true

require 'test_helper'
require 'rbconfig'
require 'timeout'
require_relative '../../examples/echo_agent'

describe ACP::AgentProcess do
  def within(seconds = 5, &)
    Timeout.timeout(seconds, &)
  end

  def allowing
    lambda { |_request|
      ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id: EchoAgent::ALLOW))
    }
  end

  def rejecting
    ->(_request) { ACP::RequestError.method_not_found }
  end

  def prompt_turn(connection)
    connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1))
    session = connection.session_new(ACP::Types::NewSessionRequest.new(cwd: Dir.pwd, mcp_servers: []))
    prompt = [ACP::Types::ContentBlock::Text.new(text: 'hello')]
    connection.session_prompt(ACP::Types::PromptRequest.new(session_id: session.session_id, prompt:)) { nil }
  end

  def wait_for_stderr(process, fragment)
    within { sleep 0.1 until process.stderr&.include?(fragment) }
  end

  describe 'driving examples/echo_agent.rb' do
    it 'completes a prompt turn' do
      response = ACP::AgentProcess.spawn(RbConfig.ruby, 'examples/echo_agent.rb', permission: allowing) do |connection|
        within { prompt_turn(connection) }
      end

      assert_equal 'end_turn', response.stop_reason
    end

    it 'terminates the child when the block exits' do
      pid = nil
      ACP::AgentProcess.spawn(RbConfig.ruby, 'examples/echo_agent.rb', permission: allowing) do |connection, process|
        pid = process.pid
        within { prompt_turn(connection) }
      end

      assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
    end
  end

  describe 'stderr' do
    it 'captures stderr when spawn is given stderr: :capture' do
      process = ACP::AgentProcess.spawn(
        RbConfig.ruby,
        '-e',
        'STDERR.puts(:boom); sleep 10',
        permission: rejecting,
        stderr: :capture
      )
      wait_for_stderr(process, 'boom')
      process.terminate

      assert_equal "boom\n", process.stderr
    end

    it 'starts the command with args, env and cwd' do
      process = ACP::AgentProcess.spawn(
        RbConfig.ruby,
        '-e',
        'STDERR.puts([Dir.pwd, ENV.fetch("ACP_TEST", nil)].join(":"))',
        cwd: File.expand_path('examples'),
        env: { 'ACP_TEST' => 'x' },
        permission: rejecting,
        stderr: :capture
      )
      wait_for_stderr(process, ':x')
      process.terminate

      assert_equal "#{File.expand_path('examples')}:x\n", process.stderr
    end
  end
end
