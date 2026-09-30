# frozen_string_literal: true

require 'test_helper'

class RecordingPeer
  attr_reader :requests

  def initialize(result)
    @result = result
    @requests = []
  end

  def request(method, params = nil)
    @requests << [method, params]
    @result
  end

  def notify(_method, _params = nil); end
end

describe ACP::AgentConnection::Client do
  def client(peer, file_system, terminal: nil)
    ACP::AgentConnection::Client.new(peer:).tap do |client|
      client.capabilities = ACP::Types::ClientCapabilities.new(fs: file_system, terminal:)
    end
  end

  let(:read) { ACP::Types::ReadTextFileRequest.new(session_id: 's', path: '/a.txt', line: 2) }
  let(:write) { ACP::Types::WriteTextFileRequest.new(session_id: 's', path: '/a.txt', content: 'hi') }

  it 'reads a text file from a client that advertises it' do
    peer = RecordingPeer.new(ACP::Transport::Result.ok({ 'content' => 'hello' }))
    response = client(peer, ACP::Types::FileSystemCapabilities.new(read_text_file: true)).read_text_file(read)

    assert_equal(
      ['hello', [['fs/read_text_file', { 'sessionId' => 's', 'path' => '/a.txt', 'line' => 2 }]]],
      [response.content, peer.requests]
    )
  end

  it 'writes a text file to a client that advertises it' do
    peer = RecordingPeer.new(ACP::Transport::Result.ok({}))
    response = client(peer, ACP::Types::FileSystemCapabilities.new(write_text_file: true)).write_text_file(write)

    assert_equal(
      [{}, [['fs/write_text_file', { 'sessionId' => 's', 'path' => '/a.txt', 'content' => 'hi' }]]],
      [response.to_h, peer.requests]
    )
  end

  it 'returns the client\'s error response' do
    error = ACP::Transport::ResponseError.new(code: -32_002, message: 'Resource not found')
    peer = RecordingPeer.new(ACP::Transport::Result.error(error))
    response = client(peer, ACP::Types::FileSystemCapabilities.new(read_text_file: true)).read_text_file(read)

    assert_same error, response
  end

  it 'refuses without a round trip what the client did not advertise' do
    peer = RecordingPeer.new(ACP::Transport::Result.ok({}))
    only_read = client(peer, ACP::Types::FileSystemCapabilities.new(read_text_file: true))
    before_initialize = ACP::AgentConnection::Client.new(peer:)
    responses = [
      only_read.write_text_file(write),
      client(peer, nil).read_text_file(read),
      before_initialize.read_text_file(read)
    ]

    assert_equal [[ACP::Transport::Stdio::METHOD_NOT_FOUND] * 3, []], [responses, peer.requests]
  end

  describe 'terminals' do
    let(:terminal) { { session_id: 's', terminal_id: 't' } }
    let(:calls) do
      {
        create_terminal: ACP::Types::CreateTerminalRequest.new(session_id: 's', command: 'ls', args: ['-a']),
        terminal_output: ACP::Types::TerminalOutputRequest.new(**terminal),
        wait_for_terminal_exit: ACP::Types::WaitForTerminalExitRequest.new(**terminal),
        kill_terminal: ACP::Types::KillTerminalRequest.new(**terminal),
        release_terminal: ACP::Types::ReleaseTerminalRequest.new(**terminal)
      }
    end

    it 'sends each terminal request to a client that advertises terminal' do
      result = { 'terminalId' => 't', 'output' => 'x', 'truncated' => false }
      peer = RecordingPeer.new(ACP::Transport::Result.ok(result))
      handle = client(peer, nil, terminal: true)
      responses = calls.map { |method, request| handle.public_send(method, request).class }
      ids = { 'sessionId' => 's', 'terminalId' => 't' }

      assert_equal(
        [
          [
            ACP::Types::CreateTerminalResponse, ACP::Types::TerminalOutputResponse,
            ACP::Types::WaitForTerminalExitResponse, ACP::Types::KillTerminalResponse,
            ACP::Types::ReleaseTerminalResponse
          ],
          [
            ['terminal/create', { 'sessionId' => 's', 'command' => 'ls', 'args' => ['-a'] }],
            ['terminal/output', ids], ['terminal/wait_for_exit', ids], ['terminal/kill', ids],
            ['terminal/release', ids]
          ]
        ],
        [responses, peer.requests]
      )
    end

    it 'refuses every terminal request without a round trip unless the client advertised terminal' do
      peer = RecordingPeer.new(ACP::Transport::Result.ok({}))
      handles = [client(peer, nil, terminal: false), ACP::AgentConnection::Client.new(peer:)]
      responses = handles.flat_map { |handle| calls.map { |method, request| handle.public_send(method, request) } }

      assert_equal [[ACP::Transport::Stdio::METHOD_NOT_FOUND] * 10, []], [responses, peer.requests]
    end
  end
end
