# frozen_string_literal: true

require 'test_helper'

require 'acp/types/unstable'

class RecordingPeer
  attr_reader :requests, :notifications, :cancelled_requests, :cancellation

  def initialize(response, cancellation: nil)
    @response = response
    @requests = []
    @notifications = []
    @cancelled_requests = []
    @cancellation = cancellation
  end

  def request(method, params = nil)
    @requests << [method, params]
    @response
  end

  def notify(method, params = nil)
    @notifications << [method, params]
  end

  def cancel_requests
    @cancelled_requests << true
  end
end

describe ACP::AgentConnection::Client do
  def client(peer, file_system, terminal: nil)
    ACP::AgentConnection::Client.new(peer:).tap do |client|
      client.capabilities = ACP::Types::ClientCapabilities.new(fs: file_system, terminal:)
    end
  end

  def permission_request
    ACP::Types::RequestPermissionRequest.new(
      session_id: 's',
      tool_call: ACP::Types::ToolCallUpdate.new(tool_call_id: 't'),
      options: []
    )
  end

  let(:read) { ACP::Types::ReadTextFileRequest.new(session_id: 's', path: '/a.txt', line: 2) }
  let(:write) { ACP::Types::WriteTextFileRequest.new(session_id: 's', path: '/a.txt', content: 'hi') }

  it 'reads a text file from a client that advertises it' do
    peer = RecordingPeer.new({ 'content' => 'hello' })
    response = client(peer, ACP::Types::FileSystemCapabilities.new(read_text_file: true)).read_text_file(read)

    assert_equal(
      ['hello', [['fs/read_text_file', { 'sessionId' => 's', 'path' => '/a.txt', 'line' => 2 }]]],
      [response.content, peer.requests]
    )
  end

  it 'writes a text file to a client that advertises it' do
    peer = RecordingPeer.new({})
    response = client(peer, ACP::Types::FileSystemCapabilities.new(write_text_file: true)).write_text_file(write)

    assert_equal(
      [{}, [['fs/write_text_file', { 'sessionId' => 's', 'path' => '/a.txt', 'content' => 'hi' }]]],
      [response.to_h, peer.requests]
    )
  end

  it 'returns the client\'s error response' do
    error = ACP::RequestError.new(code: -32_002, message: 'Resource not found')
    peer = RecordingPeer.new(error)
    response = client(peer, ACP::Types::FileSystemCapabilities.new(read_text_file: true)).read_text_file(read)

    assert_same error, response
  end

  it 'answers a reply missing a required key with invalid response' do
    error = client(RecordingPeer.new({}), nil).request_permission(permission_request)

    assert_equal [-32_603, 'Invalid response', {}], [error.code, error.message, error.data]
  end

  it 'answers a reply with a wrongly shaped value with invalid response' do
    response = { 'outcome' => [] }
    error = client(RecordingPeer.new(response), nil).request_permission(permission_request)

    assert_same response, error.data
    assert_equal [-32_603, 'Invalid response'], [error.code, error.message]
  end

  it 'answers a null result with invalid response' do
    error = client(RecordingPeer.new(nil), nil).request_permission(permission_request)

    assert_equal [-32_603, 'Invalid response', nil], [error.code, error.message, error.data]
  end

  it 'refuses without a round trip what the client did not advertise' do
    peer = RecordingPeer.new({})
    only_read = client(peer, ACP::Types::FileSystemCapabilities.new(read_text_file: true))
    before_initialize = ACP::AgentConnection::Client.new(peer:)
    refusals = [
      only_read.write_text_file(write),
      client(peer, nil).read_text_file(read),
      before_initialize.read_text_file(read)
    ]

    assert_equal(
      [[-32_601] * 3,
       ['Client does not advertise fs.writeTextFile', 'Client does not advertise fs.readTextFile',
        'Client does not advertise fs.readTextFile'],
       []],
      [refusals.map(&:code), refusals.map(&:message), peer.requests]
    )
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
      peer = RecordingPeer.new(result)
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
      peer = RecordingPeer.new({})
      handles = [client(peer, nil, terminal: false), ACP::AgentConnection::Client.new(peer:)]
      refusals = handles.flat_map { |handle| calls.map { |method, request| handle.public_send(method, request) } }

      assert_equal(
        [[-32_601] * 10, ['Client does not advertise terminal'] * 10, []],
        [refusals.map(&:code), refusals.map(&:message), peer.requests]
      )
    end
  end

  describe 'elicitation' do
    let(:form_mode) do
      ACP::Types::CreateElicitationRequest::Mode::Form.new(
        requested_schema: ACP::Types::ElicitationSchema.new(
          type: 'object', properties: { 'color' => ACP::Types::StringPropertySchema.new(title: 'Color') }
        ),
        scope: ACP::Types::ElicitationSessionScope.new(session_id: 's')
      )
    end
    let(:url_mode) do
      ACP::Types::CreateElicitationRequest::Mode::Url.new(
        elicitation_id: 'e', url: 'https://example.com', scope: ACP::Types::ElicitationSessionScope.new(session_id: 's')
      )
    end
    let(:complete) { ACP::Types::CompleteElicitationNotification.new(elicitation_id: 'e') }

    def form_request
      ACP::Types::CreateElicitationRequest.new(message: 'Pick one', mode: form_mode)
    end

    def url_request
      ACP::Types::CreateElicitationRequest.new(message: 'Visit', mode: url_mode)
    end

    def client_with(peer, elicitation)
      ACP::AgentConnection::Client.new(peer:).tap do |handle|
        handle.capabilities = ACP::Types::ClientCapabilities.new(elicitation:)
      end
    end

    def capabilities(form: nil, url: nil)
      ACP::Types::ElicitationCapabilities.new(form:, url:)
    end

    it 'sends a form-mode request to a client that advertises elicitation.form' do
      peer = RecordingPeer.new({ 'action' => 'accept', 'content' => { 'color' => 'red' } })
      response = client_with(peer, capabilities(form: ACP::Types::ElicitationFormCapabilities.new))
                 .create_elicitation(form_request)

      assert_equal(
        [ACP::Types::CreateElicitationResponse::Action::Accept,
         [['elicitation/create',
           { 'message' => 'Pick one', 'mode' => 'form', 'sessionId' => 's',
             'requestedSchema' => { 'type' => 'object', 'properties' => { 'color' => { 'title' => 'Color' } } } }]]],
        [response.action.class, peer.requests]
      )
    end

    it 'sends a url-mode request to a client that advertises elicitation.url' do
      peer = RecordingPeer.new({ 'action' => 'decline' })
      response = client_with(peer, capabilities(url: ACP::Types::ElicitationUrlCapabilities.new))
                 .create_elicitation(url_request)

      assert_equal(
        [ACP::Types::CreateElicitationResponse::Action::Decline,
         [['elicitation/create',
           { 'message' => 'Visit', 'mode' => 'url', 'elicitationId' => 'e', 'url' => 'https://example.com',
             'sessionId' => 's' }]]],
        [response.action.class, peer.requests]
      )
    end

    it 'passes an unknown response action through as-is' do
      raw_action = { 'action' => 'reschedule', 'when' => 'later' }
      response = client_with(RecordingPeer.new(raw_action), capabilities(form: ACP::Types::ElicitationFormCapabilities.new))
                 .create_elicitation(form_request)

      assert_same raw_action, response.action
    end

    it 'notifies elicitation/complete on a client that advertises elicitation.url' do
      peer = RecordingPeer.new({})
      client_with(peer, capabilities(url: ACP::Types::ElicitationUrlCapabilities.new)).complete_elicitation(complete)

      assert_equal [['elicitation/complete', { 'elicitationId' => 'e' }]], peer.notifications
    end

    it 'refuses each unadvertised mode without a round trip' do
      peer = RecordingPeer.new({})
      handle = client_with(peer, capabilities(form: ACP::Types::ElicitationFormCapabilities.new))
      before_initialize = ACP::AgentConnection::Client.new(peer:)
      refusals = [
        handle.create_elicitation(url_request),
        handle.complete_elicitation(complete),
        client_with(peer, nil).create_elicitation(form_request),
        before_initialize.create_elicitation(form_request)
      ]

      assert_equal(
        [[-32_601] * 4,
         (['Client does not advertise elicitation.url'] * 2) + (['Client does not advertise elicitation.form'] * 2),
         [], []],
        [refusals.map(&:code), refusals.map(&:message), peer.requests, peer.notifications]
      )
    end
  end

  describe 'mcp' do
    let(:request) do
      ACP::Types::Unstable::MessageMcpRequest.new(
        server_id: 'srv_1', request_id: 'mcp_1', method: 'tools/call', params: { 'name' => 'echo' }
      )
    end

    it 'sends mcp/message to a peer when the agent advertised mcpCapabilities.acp' do
      peer = RecordingPeer.new({ 'result' => { 'content' => ['hi'] } })
      response = ACP::AgentConnection::Client.new(peer:, mcp_advertised: true).mcp_message(request)

      assert_equal(
        [ACP::Types::Unstable::MessageMcpResponse::Result, { 'content' => ['hi'] }, [['mcp/message', request.to_h]]],
        [response.class, response.result, peer.requests]
      )
    end

    it 'parses an explicit null result as a present result' do
      peer = RecordingPeer.new({ 'result' => nil })
      response = ACP::AgentConnection::Client.new(peer:, mcp_advertised: true).mcp_message(request)

      assert_nil response.result
    end

    it 'refuses without a round trip unless the agent advertised mcpCapabilities.acp' do
      peer = RecordingPeer.new({})
      response = ACP::AgentConnection::Client.new(peer:).mcp_message(request)

      assert_equal(
        [-32_601, 'Agent does not advertise mcpCapabilities.acp', []],
        [response.code, response.message, peer.requests]
      )
    end
  end

  describe 'cancellation' do
    it 'cancels its outstanding client requests through the peer' do
      peer = RecordingPeer.new({})
      client(peer, nil).cancel_requests

      assert_equal [true], peer.cancelled_requests
    end

    it 'reports whether the client cancelled the request being served' do
      cancellation = ACP::Transport::Cancellation.new
      client = client(RecordingPeer.new({}, cancellation:), nil)

      refute_predicate client, :cancelled?
      cancellation.cancel

      assert_predicate client, :cancelled?
    end
  end
end
