# frozen_string_literal: true

require 'test_helper'

require 'acp/types/unstable'

class AgentConnectionClientPeer
  attr_reader :requests, :notifications, :cancel_count, :cancellation

  def initialize(response = {}, cancellation: nil)
    @response = response
    @requests = []
    @notifications = []
    @cancel_count = 0
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
    @cancel_count += 1
  end
end

class AgentConnectionClientMessage
  attr_reader :mode, :to_h

  def initialize(to_h, mode: nil)
    @to_h = to_h
    @mode = mode
  end
end

class AgentConnectionClientCancellation
  def initialize(cancelled)
    @cancelled = cancelled
  end

  def cancelled?
    @cancelled
  end
end

describe ACP::AgentConnection::Client do
  def before_initialize(peer)
    ACP::AgentConnection::Client.new(peer:)
  end

  def advertising(peer, **capabilities)
    before_initialize(peer).tap do |client|
      client.capabilities = ACP::Types::ClientCapabilities.new(**capabilities)
    end
  end

  def unadvertised(capability)
    ACP::RequestError.unadvertised(capability).to_h
  end

  let(:payload) { AgentConnectionClientMessage.new({ 'sessionId' => 's' }) }

  describe '#update' do
    it 'notifies session/update with the update wrapped in a session notification' do
      peer = AgentConnectionClientPeer.new
      update = AgentConnectionClientMessage.new({ 'sessionUpdate' => 'custom' })
      before_initialize(peer).update('s', update)

      assert_equal(
        [['session/update', ACP::Types::SessionNotification.new(session_id: 's', update:).to_h]],
        peer.notifications
      )
    end
  end

  describe '#available_commands' do
    it 'sends the commands as an available commands update' do
      peer = AgentConnectionClientPeer.new
      commands = [ACP::Types::AvailableCommand.new(name: 'plan', description: 'Make a plan')]
      before_initialize(peer).available_commands('s', commands)
      update = ACP::Types::SessionUpdate::AvailableCommandsUpdate.new(available_commands: commands)

      assert_equal(
        [['session/update', ACP::Types::SessionNotification.new(session_id: 's', update:).to_h]],
        peer.notifications
      )
    end
  end

  describe '#request_permission' do
    it 'requests session/request_permission whatever the client advertised' do
      peer = AgentConnectionClientPeer.new({ 'outcome' => { 'outcome' => 'cancelled' } })
      response = before_initialize(peer).request_permission(payload)

      assert_equal(
        [ACP::Types::RequestPermissionResponse, [['session/request_permission', payload.to_h]]],
        [response.class, peer.requests]
      )
    end
  end

  describe '#cancel_requests' do
    it 'cancels the outstanding requests through the peer' do
      peer = AgentConnectionClientPeer.new
      before_initialize(peer).cancel_requests

      assert_equal 1, peer.cancel_count
    end
  end

  describe '#cancelled?' do
    it 'is false when the peer is serving no request' do
      assert_equal [false], [before_initialize(AgentConnectionClientPeer.new).cancelled?]
    end

    it 'is false while the request being served is not cancelled' do
      peer = AgentConnectionClientPeer.new(cancellation: AgentConnectionClientCancellation.new(false))

      refute_predicate before_initialize(peer), :cancelled?
    end

    it 'is true once the request being served is cancelled' do
      peer = AgentConnectionClientPeer.new(cancellation: AgentConnectionClientCancellation.new(true))

      assert_predicate before_initialize(peer), :cancelled?
    end
  end

  describe '#read_text_file' do
    it 'refuses without a round trip unless the client advertised fs.readTextFile' do
      peer = AgentConnectionClientPeer.new({ 'content' => 'hello' })
      only_write = ACP::Types::FileSystemCapabilities.new(write_text_file: true)
      clients = [before_initialize(peer), advertising(peer), advertising(peer, fs: only_write)]

      assert_equal(
        [[unadvertised('fs.readTextFile')] * 3, []],
        [clients.map { |client| client.read_text_file(payload).to_h }, peer.requests]
      )
    end

    it 'requests fs/read_text_file from a client that advertised it' do
      peer = AgentConnectionClientPeer.new({ 'content' => 'hello' })
      only_read = ACP::Types::FileSystemCapabilities.new(read_text_file: true)
      response = advertising(peer, fs: only_read).read_text_file(payload)

      assert_equal(
        [ACP::Types::ReadTextFileResponse, [['fs/read_text_file', payload.to_h]]],
        [response.class, peer.requests]
      )
    end
  end

  describe '#write_text_file' do
    it 'refuses without a round trip unless the client advertised fs.writeTextFile' do
      peer = AgentConnectionClientPeer.new
      only_read = ACP::Types::FileSystemCapabilities.new(read_text_file: true)
      clients = [before_initialize(peer), advertising(peer), advertising(peer, fs: only_read)]

      assert_equal(
        [[unadvertised('fs.writeTextFile')] * 3, []],
        [clients.map { |client| client.write_text_file(payload).to_h }, peer.requests]
      )
    end

    it 'requests fs/write_text_file from a client that advertised it' do
      peer = AgentConnectionClientPeer.new
      only_write = ACP::Types::FileSystemCapabilities.new(write_text_file: true)
      response = advertising(peer, fs: only_write).write_text_file(payload)

      assert_equal(
        [ACP::Types::WriteTextFileResponse, [['fs/write_text_file', payload.to_h]]],
        [response.class, peer.requests]
      )
    end
  end

  {
    create_terminal: ['terminal/create', ACP::Types::CreateTerminalResponse, { 'terminalId' => 't' }],
    terminal_output: [
      'terminal/output', ACP::Types::TerminalOutputResponse, { 'output' => 'x', 'truncated' => false }
    ],
    wait_for_terminal_exit: ['terminal/wait_for_exit', ACP::Types::WaitForTerminalExitResponse, {}],
    kill_terminal: ['terminal/kill', ACP::Types::KillTerminalResponse, {}],
    release_terminal: ['terminal/release', ACP::Types::ReleaseTerminalResponse, {}]
  }.each do |method, (rpc_method, type, reply)|
    describe "##{method}" do
      it 'refuses without a round trip unless the client advertised terminal' do
        peer = AgentConnectionClientPeer.new(reply)
        clients = [before_initialize(peer), advertising(peer), advertising(peer, terminal: false)]

        assert_equal(
          [[unadvertised('terminal')] * 3, []],
          [clients.map { |client| client.public_send(method, payload).to_h }, peer.requests]
        )
      end

      it "requests #{rpc_method} from a client that advertised terminal" do
        peer = AgentConnectionClientPeer.new(reply)
        response = advertising(peer, terminal: true).public_send(method, payload)

        assert_equal [type, [[rpc_method, payload.to_h]]], [response.class, peer.requests]
      end
    end
  end

  describe 'elicitation' do
    let(:scope) { ACP::Types::ElicitationSessionScope.new(session_id: 's') }
    let(:form) do
      ACP::Types::CreateElicitationRequest::Mode::Form.new(
        requested_schema: ACP::Types::ElicitationSchema.new(type: 'object', properties: {}), scope:
      )
    end
    let(:url) do
      ACP::Types::CreateElicitationRequest::Mode::Url.new(elicitation_id: 'e', url: 'https://example.com', scope:)
    end
    let(:only_form) do
      ACP::Types::ElicitationCapabilities.new(form: ACP::Types::ElicitationFormCapabilities.new)
    end
    let(:only_url) do
      ACP::Types::ElicitationCapabilities.new(url: ACP::Types::ElicitationUrlCapabilities.new)
    end
    let(:reply) { { 'action' => 'decline' } }

    def request(mode)
      AgentConnectionClientMessage.new({ 'message' => 'Pick one' }, mode:)
    end

    describe '#create_elicitation' do
      it 'refuses a form request without a round trip unless the client advertised elicitation.form' do
        peer = AgentConnectionClientPeer.new(reply)
        clients = [before_initialize(peer), advertising(peer), advertising(peer, elicitation: only_url)]

        assert_equal(
          [[unadvertised('elicitation.form')] * 3, []],
          [clients.map { |client| client.create_elicitation(request(form)).to_h }, peer.requests]
        )
      end

      it 'refuses a url request without a round trip unless the client advertised elicitation.url' do
        peer = AgentConnectionClientPeer.new(reply)
        clients = [before_initialize(peer), advertising(peer), advertising(peer, elicitation: only_form)]

        assert_equal(
          [[unadvertised('elicitation.url')] * 3, []],
          [clients.map { |client| client.create_elicitation(request(url)).to_h }, peer.requests]
        )
      end

      it 'refuses a mode it does not know without a round trip, naming the mode' do
        peer = AgentConnectionClientPeer.new(reply)
        every_mode = ACP::Types::ElicitationCapabilities.new(form: only_form.form, url: only_url.url)
        error = advertising(peer, elicitation: every_mode).create_elicitation(request({ 'mode' => 'voice' }))

        assert_equal [unadvertised('elicitation.voice'), []], [error.to_h, peer.requests]
      end

      it 'requests elicitation/create for a form from a client that advertised elicitation.form' do
        peer = AgentConnectionClientPeer.new(reply)
        response = advertising(peer, elicitation: only_form).create_elicitation(request(form))

        assert_equal(
          [ACP::Types::CreateElicitationResponse, [['elicitation/create', request(form).to_h]]],
          [response.class, peer.requests]
        )
      end

      it 'requests elicitation/create for a url from a client that advertised elicitation.url' do
        peer = AgentConnectionClientPeer.new(reply)
        response = advertising(peer, elicitation: only_url).create_elicitation(request(url))

        assert_equal(
          [ACP::Types::CreateElicitationResponse, [['elicitation/create', request(url).to_h]]],
          [response.class, peer.requests]
        )
      end
    end

    describe '#complete_elicitation' do
      it 'refuses without notifying unless the client advertised elicitation.url' do
        peer = AgentConnectionClientPeer.new
        clients = [before_initialize(peer), advertising(peer), advertising(peer, elicitation: only_form)]

        assert_equal(
          [[unadvertised('elicitation.url')] * 3, []],
          [clients.map { |client| client.complete_elicitation(payload).to_h }, peer.notifications]
        )
      end

      it 'notifies elicitation/complete on a client that advertised elicitation.url' do
        peer = AgentConnectionClientPeer.new
        advertising(peer, elicitation: only_url).complete_elicitation(payload)

        assert_equal [['elicitation/complete', payload.to_h]], peer.notifications
      end
    end
  end

  describe '#mcp_message' do
    it 'refuses without a round trip unless the agent advertised mcpCapabilities.acp' do
      peer = AgentConnectionClientPeer.new({ 'result' => {} })
      error = before_initialize(peer).mcp_message(payload)

      assert_equal(
        [ACP::RequestError.unadvertised_agent('mcpCapabilities.acp').to_h, []],
        [error.to_h, peer.requests]
      )
    end

    it 'requests mcp/message when the agent advertised mcpCapabilities.acp' do
      peer = AgentConnectionClientPeer.new({ 'result' => {} })
      response = ACP::AgentConnection::Client.new(peer:, mcp_advertised: true).mcp_message(payload)

      parsed = ACP::Types::Unstable::MessageMcpResponse.from_h({ 'result' => {} })

      assert_equal [parsed.class, [['mcp/message', payload.to_h]]], [response.class, peer.requests]
    end
  end

  describe '#ext_request' do
    it 'raises without a round trip for a name outside the extension namespace' do
      peer = AgentConnectionClientPeer.new
      client = before_initialize(peer)

      assert_equal(
        [ArgumentError, []],
        [assert_raises(ArgumentError) { client.ext_request('session/prompt', {}) }.class, peer.requests]
      )
    end

    it 'requests the extension method and returns the unparsed result' do
      result = { 'anything' => 1 }
      peer = AgentConnectionClientPeer.new(result)
      response = before_initialize(peer).ext_request('_vendor/thing', { 'a' => 1 })

      assert_equal [result, [['_vendor/thing', { 'a' => 1 }]]], [response, peer.requests]
    end

    it 'sends no params by default' do
      peer = AgentConnectionClientPeer.new
      before_initialize(peer).ext_request('_vendor/thing')

      assert_equal [['_vendor/thing', nil]], peer.requests
    end
  end

  describe '#ext_notify' do
    it 'raises without notifying for a name outside the extension namespace' do
      peer = AgentConnectionClientPeer.new
      client = before_initialize(peer)

      assert_equal(
        [ArgumentError, []],
        [assert_raises(ArgumentError) { client.ext_notify('session/update', {}) }.class, peer.notifications]
      )
    end

    it 'notifies the extension method' do
      peer = AgentConnectionClientPeer.new
      before_initialize(peer).ext_notify('_vendor/thing', { 'a' => 1 })

      assert_equal [['_vendor/thing', { 'a' => 1 }]], peer.notifications
    end

    it 'sends no params by default' do
      peer = AgentConnectionClientPeer.new
      before_initialize(peer).ext_notify('_vendor/thing')

      assert_equal [['_vendor/thing', nil]], peer.notifications
    end
  end

  describe 'a reply to a request' do
    def invalid_response(result)
      ACP::RequestError.invalid_response(result).to_h
    end

    it 'returns the peer\'s error unparsed' do
      error = ACP::RequestError.resource_not_found
      response = before_initialize(AgentConnectionClientPeer.new(error)).request_permission(payload)

      assert_same error, response
    end

    it 'answers a result the response type rejects with invalid response' do
      error = before_initialize(AgentConnectionClientPeer.new({})).request_permission(payload)

      assert_equal invalid_response({}), error.to_h
    end

    it 'answers a null result with invalid response' do
      error = before_initialize(AgentConnectionClientPeer.new(nil)).request_permission(payload)

      assert_equal invalid_response(nil), error.to_h
    end

    it 'answers a result that is not an object with invalid response' do
      error = before_initialize(AgentConnectionClientPeer.new([])).request_permission(payload)

      assert_equal invalid_response([]), error.to_h
    end
  end
end
