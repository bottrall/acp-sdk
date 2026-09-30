# frozen_string_literal: true

require 'securerandom'
require_relative '../lib/acp/sdk'

# Serve it on stdio with `ruby examples/echo_agent.rb`.
class EchoAgent
  CAPABILITIES = ACP::Types::AgentCapabilities.new(
    load_session: true,
    session_capabilities: ACP::Types::SessionCapabilities.new(list: ACP::Types::SessionListCapabilities.new)
  )
  COMMANDS = [ACP::Types::AvailableCommand.new(name: 'echo', description: 'Echo the prompt back')].freeze
  ALLOW = 'allow'
  OPTIONS = [
    ACP::Types::PermissionOption.new(option_id: ALLOW, name: 'Allow', kind: ACP::Types::PermissionOptionKind::ALLOW_ONCE),
    ACP::Types::PermissionOption.new(option_id: 'reject', name: 'Reject', kind: ACP::Types::PermissionOptionKind::REJECT_ONCE)
  ].freeze
  NOT_FOUND = ACP::Transport::ResponseError.new(code: -32_002, message: 'Resource not found')

  class Session
    attr_reader :cwd, :history

    def initialize(cwd:, history: [])
      @cwd = cwd
      @history = history
      freeze
    end

    def with_history(updates)
      Session.new(cwd:, history: history + updates)
    end
  end

  def initialize(client:)
    @client = client
    @lock = Mutex.new
    @sessions = {}
    @cancelled = Set.new
  end

  def new_session(request)
    session_id = "sess_#{SecureRandom.hex(8)}"
    @lock.synchronize { @sessions[session_id] = Session.new(cwd: request.cwd) }
    ACP::Types::NewSessionResponse.new(session_id:)
  end

  def session_created(response)
    @client.available_commands(response.session_id, COMMANDS)
  end

  def prompt(request)
    session_id = request.session_id
    return NOT_FOUND unless begin_turn(session_id)

    blocks = request.prompt.grep(ACP::Types::ContentBlock::Text)
    record(session_id, blocks.map { |block| ACP::Types::SessionUpdate::UserMessageChunk.new(content: block) })
    permission = ask_permission(session_id)
    return permission if permission.is_a?(ACP::Transport::ResponseError)
    return ACP::Types::PromptResponse.new(stop_reason: ACP::Types::StopReason::CANCELLED) if cancelled?(
      session_id,
      permission
    )

    reply = respond(session_id, blocks) if allowed?(permission)
    return reply if reply.is_a?(ACP::Transport::ResponseError)

    ACP::Types::PromptResponse.new(stop_reason: ACP::Types::StopReason::END_TURN)
  end

  def cancel(notification)
    @lock.synchronize { @cancelled << notification.session_id }
  end

  def load_session(request)
    history = @lock.synchronize { @sessions[request.session_id]&.history }
    return NOT_FOUND unless history

    history.each { |update| @client.update(request.session_id, update) }
    ACP::Types::LoadSessionResponse.new
  end

  def list_sessions(request)
    sessions = @lock.synchronize { @sessions.dup }
    infos = sessions.filter_map do |session_id, session|
      ACP::Types::SessionInfo.new(session_id:, cwd: session.cwd) if request.cwd.nil? || request.cwd == session.cwd
    end
    ACP::Types::ListSessionsResponse.new(sessions: infos)
  end

  private

  def begin_turn(session_id)
    @lock.synchronize do
      @cancelled.delete(session_id)
      @sessions.key?(session_id)
    end
  end

  def ask_permission(session_id)
    tool_call_id = "echo_#{SecureRandom.hex(4)}"
    title = 'Echo the prompt'
    @client.update(session_id, ACP::Types::SessionUpdate::ToolCall.new(tool_call_id:, title:, status: 'pending'))
    @client.request_permission(
      ACP::Types::RequestPermissionRequest.new(
        session_id:,
        tool_call: ACP::Types::ToolCallUpdate.new(tool_call_id:, title:),
        options: OPTIONS
      )
    )
  end

  def cancelled?(session_id, permission)
    permission.outcome.is_a?(ACP::Types::RequestPermissionOutcome::Cancelled) ||
      @lock.synchronize { @cancelled.include?(session_id) }
  end

  def allowed?(permission)
    outcome = permission.outcome
    outcome.is_a?(ACP::Types::RequestPermissionOutcome::Selected) && outcome.option_id == ALLOW
  end

  # `/read <path>` echoes the file, `/write <path> <text>` writes it and
  # `/run <command> [args]` echoes its output, all through the client; any
  # other prompt is echoed as is.
  def respond(session_id, blocks)
    case blocks.first&.text
    when %r{\A/read (\S+)\z} then read(session_id, Regexp.last_match(1))
    when %r{\A/run (.+)\z} then run(session_id, *Regexp.last_match(1).split)
    when %r{\A/write (\S+) (.*)\z}m
      @client.write_text_file(
        ACP::Types::WriteTextFileRequest.new(session_id:, path: Regexp.last_match(1), content: Regexp.last_match(2))
      )
    else echo(session_id, blocks)
    end
  end

  def read(session_id, path)
    file = @client.read_text_file(ACP::Types::ReadTextFileRequest.new(session_id:, path:))
    return file if file.is_a?(ACP::Transport::ResponseError)

    echo(session_id, [ACP::Types::ContentBlock::Text.new(text: file.content)])
  end

  def run(session_id, command, *args)
    terminal = @client.create_terminal(ACP::Types::CreateTerminalRequest.new(session_id:, command:, args:))
    return terminal if terminal.is_a?(ACP::Transport::ResponseError)

    output = finish(session_id, terminal.terminal_id)
    return output if output.is_a?(ACP::Transport::ResponseError)

    echo(session_id, [ACP::Types::ContentBlock::Text.new(text: output.output)])
  end

  # ACP leaves releasing a terminal to the agent, even when waiting on it fails.
  def finish(session_id, terminal_id)
    status = @client.wait_for_terminal_exit(ACP::Types::WaitForTerminalExitRequest.new(session_id:, terminal_id:))
    output =
      if status.is_a?(ACP::Transport::ResponseError) then status
      else @client.terminal_output(ACP::Types::TerminalOutputRequest.new(session_id:, terminal_id:))
      end
    @client.release_terminal(ACP::Types::ReleaseTerminalRequest.new(session_id:, terminal_id:))
    output
  end

  def echo(session_id, blocks)
    chunks = blocks.map { |block| ACP::Types::SessionUpdate::AgentMessageChunk.new(content: block) }
    chunks.each { |chunk| @client.update(session_id, chunk) }
    record(session_id, chunks)
  end

  def record(session_id, updates)
    @lock.synchronize do
      @sessions[session_id] = @sessions.fetch(session_id).with_history(updates)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ACP::AgentConnection.new(
    transport: ACP::Transport::Stdio.new(input: $stdin, output: $stdout),
    capabilities: EchoAgent::CAPABILITIES,
    agent_info: ACP::Types::Implementation.new(name: 'echo-agent', version: ACP::VERSION)
  ) { |client| EchoAgent.new(client:) }.start.join
end
