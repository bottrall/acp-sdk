# frozen_string_literal: true

require 'test_helper'
require_relative '../../examples/echo_agent'

class EchoAgentClient
  REQUESTS = %i[
    request_permission
    read_text_file
    write_text_file
    create_terminal
    wait_for_terminal_exit
    terminal_output
    release_terminal
  ].freeze

  attr_reader :capabilities, :calls

  def initialize(capabilities:, replies:)
    @capabilities = capabilities
    @replies = replies
    @calls = []
  end

  def update(session_id, update)
    @calls << [:update, session_id, update]
  end

  def available_commands(session_id, commands)
    @calls << [:available_commands, session_id, commands]
  end

  REQUESTS.each do |name|
    define_method(name) do |request|
      @calls << [name, request]
      reply = @replies.fetch(name)
      reply.respond_to?(:call) ? reply.call(request) : reply
    end
  end
end

describe EchoAgent do
  def selected(option_id)
    ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id:))
  end

  def start(capabilities: nil, **replies)
    @client = EchoAgentClient.new(
      capabilities:,
      replies: { request_permission: selected(EchoAgent::ALLOW), **replies }
    )
    @agent = EchoAgent.new(client: @client)
    @session_id = open_session('/work')
  end

  def open_session(cwd)
    @agent.new_session(ACP::Types::NewSessionRequest.new(cwd:, mcp_servers: [])).session_id
  end

  def announced(**capabilities)
    start(capabilities: ACP::Types::ClientCapabilities.new(**capabilities))
    @agent.session_created(ACP::Types::NewSessionResponse.new(session_id: @session_id))
    @client.calls
  end

  def prompt(*texts, session_id: @session_id)
    blocks = texts.map { |text| ACP::Types::ContentBlock::Text.new(text:) }
    @agent.prompt(ACP::Types::PromptRequest.new(session_id:, prompt: blocks))
  end

  def cancel(session_id)
    @agent.cancel(ACP::Types::CancelNotification.new(session_id:))
  end

  def load(session_id)
    @agent.load_session(ACP::Types::LoadSessionRequest.new(session_id:, cwd: '/work', mcp_servers: []))
  end

  def listed(cwd = nil)
    @agent.list_sessions(ACP::Types::ListSessionsRequest.new(cwd:)).sessions.map do |info|
      [info.session_id, info.cwd]
    end
  end

  def sent(name)
    @client.calls.filter_map { |call, request| request if call == name }
  end

  def names
    @client.calls.map(&:first)
  end

  def echoed
    @client.calls.filter_map do |_, _, update|
      update.content.text if update.is_a?(ACP::Types::SessionUpdate::AgentMessageChunk)
    end
  end

  def terminal(**replies)
    {
      create_terminal: ACP::Types::CreateTerminalResponse.new(terminal_id: 'term_1'),
      wait_for_terminal_exit: ACP::Types::WaitForTerminalExitResponse.new(exit_code: 0),
      terminal_output: ACP::Types::TerminalOutputResponse.new(output: 'ran', truncated: false),
      release_terminal: ACP::Types::ReleaseTerminalResponse.new,
      **replies
    }
  end

  describe EchoAgent::Session do
    it 'returns a session with the updates appended, leaving the original as it was' do
      original = EchoAgent::Session.new(cwd: '/work', history: [:first])
      extended = original.with_history([:second])

      assert_equal(
        [['/work', %i[first second]], ['/work', [:first]]],
        [[extended.cwd, extended.history], [original.cwd, original.history]]
      )
    end
  end

  describe '#new_session' do
    it 'gives each session its own id' do
      start

      assert_equal 2, [@session_id, open_session('/work')].grep(/\Asess_\h{16}\z/).uniq.size
    end

    it 'remembers the working directory the session was opened in' do
      start

      assert_equal [[@session_id, '/work']], listed
    end
  end

  describe '#session_created' do
    it 'offers no commands to a client that sent no capabilities' do
      start
      @agent.session_created(ACP::Types::NewSessionResponse.new(session_id: @session_id))

      assert_equal [[:available_commands, @session_id, []]], @client.calls
    end

    it 'offers no commands to a client that advertises neither files nor terminals' do
      calls = announced

      assert_equal [[:available_commands, @session_id, []]], calls
    end

    it 'offers read to a client that reads files' do
      calls = announced(fs: ACP::Types::FileSystemCapabilities.new(read_text_file: true))

      assert_equal [[:available_commands, @session_id, [EchoAgent::READ]]], calls
    end

    it 'offers write to a client that writes files' do
      calls = announced(fs: ACP::Types::FileSystemCapabilities.new(write_text_file: true))

      assert_equal [[:available_commands, @session_id, [EchoAgent::WRITE]]], calls
    end

    it 'offers run to a client with terminals' do
      calls = announced(terminal: true)

      assert_equal [[:available_commands, @session_id, [EchoAgent::RUN]]], calls
    end

    it 'offers every command to a client that advertises everything' do
      calls = announced(
        fs: ACP::Types::FileSystemCapabilities.new(read_text_file: true, write_text_file: true),
        terminal: true
      )

      assert_equal [[:available_commands, @session_id, [EchoAgent::READ, EchoAgent::WRITE, EchoAgent::RUN]]], calls
    end
  end

  describe '#prompt' do
    it 'refuses an unknown session without contacting the client' do
      start

      assert_equal [EchoAgent::NOT_FOUND, []], [prompt('hello', session_id: 'sess_missing'), @client.calls]
    end

    it 'forgets a cancellation made before the turn began' do
      start
      cancel(@session_id)

      assert_equal ACP::Types::StopReason::END_TURN, prompt('hello').stop_reason
    end

    it 'echoes only the text blocks of a prompt' do
      start
      image = ACP::Types::ContentBlock::Image.new(data: 'AAAA', mime_type: 'image/png')
      text = ACP::Types::ContentBlock::Text.new(text: 'hello')
      @agent.prompt(ACP::Types::PromptRequest.new(session_id: @session_id, prompt: [image, text]))

      assert_equal ['hello'], echoed
    end

    it 'records the user message even when the turn is not allowed to echo' do
      start(request_permission: selected('reject'))
      prompt('hello')
      turn = @client.calls.size
      load(@session_id)

      assert_equal(
        [[ACP::Types::SessionUpdate::UserMessageChunk, 'hello']],
        @client.calls.drop(turn).map { |_, _, update| [update.class, update.content.text] }
      )
    end

    it 'announces a pending tool call before asking permission for it' do
      start
      prompt('hello')
      (name, session_id, tool_call), (asked, request) = @client.calls

      assert_equal(
        [:update, @session_id, 'pending', request.tool_call.tool_call_id, :request_permission],
        [name, session_id, tool_call.status, tool_call.tool_call_id, asked]
      )
    end

    it 'asks permission in the session with the allow and reject options' do
      start
      prompt('hello')
      request = sent(:request_permission).first

      assert_equal [@session_id, EchoAgent::OPTIONS], [request.session_id, request.options]
    end

    it 'returns a failed permission request and echoes nothing' do
      error = ACP::RequestError.internal_error
      start(request_permission: error)

      assert_equal [error, []], [prompt('hello'), echoed]
    end

    it 'stops as cancelled when the permission request is cancelled' do
      start(
        request_permission: ACP::Types::RequestPermissionResponse.new(
          outcome: ACP::Types::RequestPermissionOutcome::Cancelled.new
        )
      )

      assert_equal [ACP::Types::StopReason::CANCELLED, []], [prompt('hello').stop_reason, echoed]
    end

    it 'ends the turn without echoing when permission is rejected' do
      start(request_permission: selected('reject'))

      assert_equal [ACP::Types::StopReason::END_TURN, []], [prompt('hello').stop_reason, echoed]
    end

    it 'echoes each text block and ends the turn when permission is allowed' do
      start

      assert_equal [ACP::Types::StopReason::END_TURN, %w[hello there]], [prompt('hello', 'there').stop_reason, echoed]
    end

    it 'echoes nothing for a prompt with no text' do
      start

      assert_equal [ACP::Types::StopReason::END_TURN, []], [prompt.stop_reason, echoed]
    end

    it 'echoes a command given no argument' do
      start
      prompt('/read')

      assert_equal [['/read'], []], [echoed, sent(:read_text_file)]
    end

    describe 'with /read' do
      it 'asks the client for the rest of the line as a path' do
        start(read_text_file: ACP::Types::ReadTextFileResponse.new(content: 'contents'))
        prompt('/read my notes.txt')

        assert_equal(
          [[@session_id, 'my notes.txt']],
          sent(:read_text_file).map { |request| [request.session_id, request.path] }
        )
      end

      it 'returns a failed read and echoes nothing' do
        error = ACP::RequestError.resource_not_found
        start(read_text_file: error)

        assert_equal [error, []], [prompt('/read notes.txt'), echoed]
      end

      it 'echoes the content of the file' do
        start(read_text_file: ACP::Types::ReadTextFileResponse.new(content: 'contents'))

        assert_equal(
          [ACP::Types::StopReason::END_TURN, ['contents']],
          [prompt('/read notes.txt').stop_reason, echoed]
        )
      end
    end

    describe 'with /write' do
      it 'writes the text after the path to the path' do
        start(write_text_file: ACP::Types::WriteTextFileResponse.new)
        prompt('/write notes.txt hello there')

        assert_equal(
          [[@session_id, 'notes.txt', 'hello there']],
          sent(:write_text_file).map { |request| [request.session_id, request.path, request.content] }
        )
      end

      it 'writes an empty file when no text follows the path' do
        start(write_text_file: ACP::Types::WriteTextFileResponse.new)
        prompt('/write notes.txt')

        assert_equal([['notes.txt', '']], sent(:write_text_file).map { |request| [request.path, request.content] })
      end

      it 'returns a failed write' do
        error = ACP::RequestError.internal_error
        start(write_text_file: error)

        assert_same error, prompt('/write notes.txt hello')
      end

      it 'ends the turn without echoing once the file is written' do
        start(write_text_file: ACP::Types::WriteTextFileResponse.new)

        assert_equal([ACP::Types::StopReason::END_TURN, []], [prompt('/write notes.txt hello').stop_reason, echoed])
      end
    end

    describe 'with /run' do
      it 'rejects an unbalanced command line without creating a terminal' do
        start(**terminal)

        assert_equal(
          [ACP::RequestError::INVALID_PARAMS, []],
          [prompt('/run echo "hello').code, sent(:create_terminal)]
        )
      end

      it 'creates a terminal for the command with its shell-split arguments' do
        start(**terminal)
        prompt('/run echo "hello there" friend')

        assert_equal(
          [[@session_id, 'echo', ['hello there', 'friend']]],
          sent(:create_terminal).map { |request| [request.session_id, request.command, request.args] }
        )
      end

      it 'returns a failed terminal creation without waiting on or releasing anything' do
        error = ACP::RequestError.internal_error
        start(**terminal(create_terminal: error))

        assert_equal([error, %i[update request_permission create_terminal]], [prompt('/run echo hello'), names])
      end

      it 'waits on, reads and releases the terminal it created' do
        start(**terminal)
        prompt('/run echo hello')
        requests = %i[wait_for_terminal_exit terminal_output release_terminal].flat_map { |name| sent(name) }

        assert_equal(
          [[@session_id, 'term_1']] * 3,
          requests.map do |request|
            [request.session_id, request.terminal_id]
          end
        )
      end

      it 'returns a failed wait, releasing the terminal without reading its output' do
        error = ACP::RequestError.internal_error
        start(**terminal(wait_for_terminal_exit: error))

        assert_equal(
          [error, %i[create_terminal wait_for_terminal_exit release_terminal]],
          [prompt('/run echo hello'), names.drop(2)]
        )
      end

      it 'returns a failed output read after releasing the terminal' do
        error = ACP::RequestError.internal_error
        start(**terminal(terminal_output: error))

        assert_equal(
          [error, %i[create_terminal wait_for_terminal_exit terminal_output release_terminal]],
          [prompt('/run echo hello'), names.drop(2)]
        )
      end

      it 'echoes the output once the terminal is released' do
        start(**terminal)

        assert_equal(
          [ACP::Types::StopReason::END_TURN, ['ran'], %i[release_terminal update]],
          [prompt('/run echo hello').stop_reason, echoed, names.last(2)]
        )
      end
    end

    it 'echoes text that names no command' do
      start
      prompt('hello there')

      assert_equal ['hello there'], echoed
    end
  end

  describe '#cancel' do
    it 'stops the turn in progress as cancelled, whatever the permission outcome' do
      start(
        request_permission: lambda do |request|
          cancel(request.session_id)
          selected(EchoAgent::ALLOW)
        end
      )

      assert_equal [ACP::Types::StopReason::CANCELLED, []], [prompt('hello').stop_reason, echoed]
    end

    it 'leaves the turns of other sessions running' do
      start(
        request_permission: lambda do |_request|
          cancel('sess_other')
          selected(EchoAgent::ALLOW)
        end
      )

      assert_equal ACP::Types::StopReason::END_TURN, prompt('hello').stop_reason
    end
  end

  describe '#load_session' do
    it 'refuses an unknown session without replaying anything' do
      start

      assert_equal [EchoAgent::NOT_FOUND, []], [load('sess_missing'), @client.calls]
    end

    it 'replays nothing for a session that has had no turn' do
      start

      assert_equal [ACP::Types::LoadSessionResponse, []], [load(@session_id).class, @client.calls]
    end

    it 'replays the user and agent messages of earlier turns in order' do
      start
      prompt('hello')
      prompt('again')
      turns = @client.calls.size
      load(@session_id)

      assert_equal(
        [
          [:update, @session_id, ACP::Types::SessionUpdate::UserMessageChunk, 'hello'],
          [:update, @session_id, ACP::Types::SessionUpdate::AgentMessageChunk, 'hello'],
          [:update, @session_id, ACP::Types::SessionUpdate::UserMessageChunk, 'again'],
          [:update, @session_id, ACP::Types::SessionUpdate::AgentMessageChunk, 'again']
        ],
        @client.calls.drop(turns).map { |name, id, update| [name, id, update.class, update.content.text] }
      )
    end
  end

  describe '#list_sessions' do
    it 'lists every session when no working directory is given' do
      start
      other = open_session('/elsewhere')

      assert_equal [[@session_id, '/work'], [other, '/elsewhere']], listed
    end

    it 'lists only the sessions opened in the given working directory' do
      start
      other = open_session('/elsewhere')

      assert_equal [[other, '/elsewhere']], listed('/elsewhere')
    end
  end

  describe '#resume_session' do
    def resume(session_id)
      @agent.resume_session(ACP::Types::ResumeSessionRequest.new(session_id:, cwd: '/work'))
    end

    it 'refuses an unknown session' do
      start

      assert_same EchoAgent::NOT_FOUND, resume('sess_missing')
    end

    it 'resumes a known session without replaying its history' do
      start
      prompt('hello')
      turn = @client.calls.size

      assert_equal [ACP::Types::ResumeSessionResponse, []], [resume(@session_id).class, @client.calls.drop(turn)]
    end
  end

  describe '#close_session' do
    def close(session_id)
      @agent.close_session(ACP::Types::CloseSessionRequest.new(session_id:))
    end

    it 'refuses an unknown session' do
      start

      assert_same EchoAgent::NOT_FOUND, close('sess_missing')
    end

    it 'forgets the session' do
      start

      assert_equal [ACP::Types::CloseSessionResponse, []], [close(@session_id).class, listed]
    end
  end

  describe '#delete_session' do
    def delete(session_id)
      @agent.delete_session(ACP::Types::DeleteSessionRequest.new(session_id:))
    end

    it 'refuses an unknown session' do
      start

      assert_same EchoAgent::NOT_FOUND, delete('sess_missing')
    end

    it 'forgets the session' do
      start

      assert_equal [ACP::Types::DeleteSessionResponse, []], [delete(@session_id).class, listed]
    end
  end
end
