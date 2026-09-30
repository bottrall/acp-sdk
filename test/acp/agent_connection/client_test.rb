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
  def client(peer, file_system)
    ACP::AgentConnection::Client.new(peer:).tap do |client|
      client.capabilities = ACP::Types::ClientCapabilities.new(fs: file_system)
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
end
