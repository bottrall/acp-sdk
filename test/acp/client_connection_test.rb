# frozen_string_literal: true

require 'test_helper'
require 'open3'

require 'acp/types/unstable'

class ClientConnectionTransport
  attr_reader :replies, :handlers, :notification_handlers, :reader
  attr_accessor :cancellation

  def initialize(log)
    @log = log
    @replies = { 'initialize' => { 'protocolVersion' => 1 } }
    @reader = Thread.new { nil }
  end

  def start(requests:, notifications:)
    @handlers = requests
    @notification_handlers = notifications
    @reader
  end

  def request(method, params = nil)
    @log << [:request, method, params]
    @replies[method]
  end

  def notify(method, params = nil)
    @log << [:notify, method, params]
    nil
  end
end

class ClientConnectionStreams
  attr_writer :reply, :updates

  def initialize(log)
    @log = log
    @reply = nil
    @updates = []
  end

  def stream(session_id, method, params, &)
    @log << [:stream, session_id, method, params]
    @updates.each(&)
    @reply
  end

  def request_permission(params)
    @log << [:request_permission, params]
    :permission_answer
  end

  def dispatch(params)
    @log << [:dispatch, params]
  end

  def cancel(session_id)
    @log << [:cancel, session_id]
  end
end

class ClientConnectionInbound
  attr_accessor :refusal

  def initialize(log)
    @log = log
  end

  def requests
    { 'inbound/request' => :inbound_request }
  end

  def notifications
    { 'inbound/notification' => :inbound_notification }
  end

  def advertise(capabilities)
    @log << [:advertise, capabilities]
    raise refusal if refusal
  end

  def mcp_advertised=(advertised)
    @log << [:mcp_advertised, advertised]
  end
end

class ClientConnectionCancellation
  def initialize(answer)
    @answer = answer
  end

  def cancelled?
    @answer
  end
end

describe ACP::ClientConnection do
  before do
    @log = []
    @transport = ClientConnectionTransport.new(@log)
    @streams = ClientConnectionStreams.new(@log)
    @inbound = ClientConnectionInbound.new(@log)
  end

  def connection
    ACP::ClientConnection.new(transport: @transport, streams: @streams, inbound: @inbound)
  end

  def built(**)
    ACP::ClientConnection.build(transport: @transport, permission: ->(_request) {}, **).tap(&:start)
  end

  def route(wire)
    @transport.handlers.fetch(wire)
  end

  def initialize_request(**capabilities)
    ACP::Types::InitializeRequest.new(
      protocol_version: 1,
      client_capabilities: (ACP::Types::ClientCapabilities.new(**capabilities) unless capabilities.empty?)
    )
  end

  def fs(**)
    ACP::Types::FileSystemCapabilities.new(**)
  end

  def modes(*names)
    ACP::Types::ElicitationCapabilities.new(
      form: (ACP::Types::ElicitationFormCapabilities.new if names.include?(:form)),
      url: (ACP::Types::ElicitationUrlCapabilities.new if names.include?(:url))
    )
  end

  def url_params
    {
      'sessionId' => 's', 'mode' => 'url', 'elicitationId' => 'e1',
      'url' => 'https://example.com/connect', 'message' => 'Authorize access'
    }
  end

  def recording(name, answer = nil)
    lambda do |request|
      @log << [name, request.class]
      answer
    end
  end

  def handler(**methods)
    log = @log
    Object.new.tap do |object|
      methods.each do |name, answer|
        object.define_singleton_method(name) do |argument|
          log << [name, argument.class]
          answer
        end
      end
    end
  end

  def self.it_sends(method, wire, request, reply, response)
    it "sends #{wire} with the request and parses the reply as #{response.name}" do
      @transport.replies[wire] = reply
      answer = connection.public_send(method, request)

      assert_equal([[[:request, wire, request.to_h]], response], [@log, answer.class])
    end
  end

  describe '.build' do
    it 'wires streams that send through the transport' do
      @transport.replies['session/prompt'] = { 'stopReason' => 'end_turn' }
      request = ACP::Types::PromptRequest.new(session_id: 's1', prompt: [])
      answer = built.prompt_session(request) { nil }

      assert_equal([[[:request, 'session/prompt', request.to_h]], 'end_turn'], [@log, answer.stop_reason])
    end

    it 'wires the permission handler to session/request_permission' do
      answer = ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Cancelled.new)
      built(permission: recording(:permission, answer))
      reply = route('session/request_permission').call(
        { 'sessionId' => 's', 'toolCall' => { 'toolCallId' => 'c1' }, 'options' => [] }
      )

      assert_equal([answer, [[:permission, ACP::Types::RequestPermissionRequest]]], [reply, @log])
    end

    it 'wires the updates handler to session/update' do
      built(updates: recording(:updates))
      update = { 'sessionUpdate' => 'agent_message_chunk', 'content' => { 'type' => 'text', 'text' => 'hi' } }
      @transport.notification_handlers.fetch('session/update').call({ 'sessionId' => 's', 'update' => update })

      assert_equal [[:updates, ACP::Types::SessionNotification]], @log
    end

    it 'wires the fs and terminal handler objects to their routes' do
      client = built(fs: handler(read_text_file: :read), terminal: handler(kill_terminal: :killed))
      client.connect(initialize_request(fs: fs(read_text_file: true), terminal: false))
      @log.clear
      replies = [
        route('fs/read_text_file').call({ 'sessionId' => 's', 'path' => '/a.txt' }),
        route('terminal/kill').call({ 'sessionId' => 's', 'terminalId' => 't1' })
      ]

      assert_equal(
        [[:read, ACP::RequestError.unadvertised('terminal').to_h], [[:read_text_file, ACP::Types::ReadTextFileRequest]]],
        [[replies[0], replies[1].to_h], @log]
      )
    end

    it 'wires the elicitation handler object to elicitation/create and elicitation/complete' do
      client = built(elicitation: handler(create_elicitation: :created, complete_elicitation: nil))
      client.connect(initialize_request(elicitation: modes(:url)))
      @log.clear
      reply = route('elicitation/create').call(url_params)
      @transport.notification_handlers.fetch('elicitation/complete').call({ 'elicitationId' => 'e1' })

      assert_equal(
        [:created, [
          [:create_elicitation, ACP::Types::CreateElicitationRequest],
          [:complete_elicitation, ACP::Types::CompleteElicitationNotification]
        ]],
        [reply, @log]
      )
    end

    it 'wires the mcp_message handler and the extension handlers' do
      mcp = ->(_request) {}
      request = ->(_params) {}
      notification = ->(_params) {}
      built(
        mcp_message: mcp,
        extension_requests: { '_myapp/ping' => request },
        extension_notifications: { '_myapp/note' => notification }
      )

      assert_equal(
        [true, true, true],
        [
          @transport.handlers.key?('mcp/message'),
          route('_myapp/ping').equal?(request),
          @transport.notification_handlers.fetch('_myapp/note').equal?(notification)
        ]
      )
    end
  end

  describe 'start' do
    it "returns the transport's reader thread" do
      assert_same @transport.reader, connection.start
    end

    it 'routes session/request_permission to the streams, beside the inbound requests' do
      connection.start
      answer = route('session/request_permission').call(:params)

      assert_equal(
        [[%i[request_permission params]], :permission_answer, :inbound_request],
        [@log, answer, route('inbound/request')]
      )
    end

    it 'routes session/update to the streams, beside the inbound notifications' do
      connection.start
      @transport.notification_handlers.fetch('session/update').call(:update)

      assert_equal(
        [[%i[dispatch update]], :inbound_notification],
        [@log, @transport.notification_handlers.fetch('inbound/notification')]
      )
    end
  end

  describe 'connect' do
    it 'advertises the client capabilities to the inbound side before sending initialize' do
      request = initialize_request(terminal: true)
      connection.connect(request)

      assert_equal(
        [[:advertise, request.client_capabilities], [:request, 'initialize', request.to_h], [:mcp_advertised, false]],
        @log
      )
    end

    it 'sends nothing when the inbound side refuses the capabilities' do
      @inbound.refusal = ArgumentError.new('unserved')
      request = initialize_request(terminal: true)
      error = assert_raises(ArgumentError) { connection.connect(request) }

      assert_equal ['unserved', [[:advertise, request.client_capabilities]]], [error.message, @log]
    end

    it 'tells the inbound side the agent advertised mcpCapabilities.acp when its reply does' do
      @transport.replies['initialize'] = {
        'protocolVersion' => 1, 'agentCapabilities' => { 'mcpCapabilities' => { 'acp' => true } }
      }
      connection.connect(initialize_request)

      assert_equal [:mcp_advertised, true], @log.last
    end

    it "returns the agent's error" do
      error = ACP::RequestError.auth_required
      @transport.replies['initialize'] = error

      assert_same error, connection.connect(initialize_request)
    end

    it 'answers a reply that does not parse with invalid response' do
      @transport.replies['initialize'] = {}

      assert_equal ACP::RequestError.invalid_response({}).to_h, connection.connect(initialize_request).to_h
    end

    it 'sends initialize with the request and parses the reply as InitializeResponse' do
      request = initialize_request
      answer = connection.connect(request)

      assert_equal(
        [[:request, 'initialize', request.to_h], ACP::Types::InitializeResponse],
        [@log.find { |entry| entry.first == :request }, answer.class]
      )
    end

    it 'answers a reply naming another protocol version with the unsupported version error' do
      @transport.replies['initialize'] = { 'protocolVersion' => 2 }

      assert_equal(
        ACP::RequestError.unsupported_protocol_version(requested: 1, returned: 2).to_h,
        connection.connect(initialize_request).to_h
      )
    end
  end

  it_sends(
    :new_session,
    'session/new',
    ACP::Types::NewSessionRequest.new(cwd: '/work', mcp_servers: []),
    { 'sessionId' => 's1' },
    ACP::Types::NewSessionResponse
  )

  describe 'prompt_session' do
    it 'streams session/prompt for the session, yields its updates and parses the reply as PromptResponse' do
      @streams.updates = %i[first second]
      @streams.reply = { 'stopReason' => 'end_turn' }
      request = ACP::Types::PromptRequest.new(session_id: 's1', prompt: [])
      yielded = []
      answer = connection.prompt_session(request) { |update| yielded << update }

      assert_equal(
        [[[:stream, 's1', 'session/prompt', request.to_h]], %i[first second], ACP::Types::PromptResponse],
        [@log, yielded, answer.class]
      )
    end
  end

  describe 'load_session' do
    it 'streams session/load for the session, yields its updates and parses the reply as LoadSessionResponse' do
      @streams.updates = %i[first second]
      @streams.reply = {}
      request = ACP::Types::LoadSessionRequest.new(session_id: 's1', cwd: '/work', mcp_servers: [])
      yielded = []
      answer = connection.load_session(request) { |update| yielded << update }

      assert_equal(
        [[[:stream, 's1', 'session/load', request.to_h]], %i[first second], ACP::Types::LoadSessionResponse],
        [@log, yielded, answer.class]
      )
    end
  end

  it_sends(
    :list_sessions,
    'session/list',
    ACP::Types::ListSessionsRequest.new(cwd: '/work'),
    { 'sessions' => [] },
    ACP::Types::ListSessionsResponse
  )

  it_sends(
    :resume_session,
    'session/resume',
    ACP::Types::ResumeSessionRequest.new(session_id: 's1', cwd: '/work'),
    {},
    ACP::Types::ResumeSessionResponse
  )

  it_sends(
    :close_session,
    'session/close',
    ACP::Types::CloseSessionRequest.new(session_id: 's1'),
    {},
    ACP::Types::CloseSessionResponse
  )

  it_sends(
    :delete_session,
    'session/delete',
    ACP::Types::DeleteSessionRequest.new(session_id: 's1'),
    {},
    ACP::Types::DeleteSessionResponse
  )

  it_sends(
    :fork_session,
    'session/fork',
    ACP::Types::Unstable::ForkSessionRequest.new(session_id: 's1', cwd: '/work'),
    { 'sessionId' => 's2' },
    ACP::Types::Unstable::ForkSessionResponse
  )

  it_sends(
    :list_providers,
    'providers/list',
    ACP::Types::Unstable::ListProvidersRequest.new,
    { 'providers' => [] },
    ACP::Types::Unstable::ListProvidersResponse
  )

  it_sends(
    :set_provider,
    'providers/set',
    ACP::Types::Unstable::SetProviderRequest.new(
      provider_id: 'anthropic', api_type: 'anthropic', base_url: 'https://api.example.com'
    ),
    {},
    ACP::Types::Unstable::SetProviderResponse
  )

  it_sends(
    :disable_provider,
    'providers/disable',
    ACP::Types::Unstable::DisableProviderRequest.new(provider_id: 'anthropic'),
    {},
    ACP::Types::Unstable::DisableProviderResponse
  )

  describe 'cancel_session' do
    it 'notifies session/cancel, then cancels the pending permission requests of the session' do
      notification = ACP::Types::CancelNotification.new(session_id: 's1')
      connection.cancel_session(notification)

      assert_equal [[:notify, 'session/cancel', notification.to_h], [:cancel, 's1']], @log
    end
  end

  it_sends(
    :set_session_mode,
    'session/set_mode',
    ACP::Types::SetSessionModeRequest.new(session_id: 's1', mode_id: 'code'),
    {},
    ACP::Types::SetSessionModeResponse
  )

  it_sends(
    :set_session_config_option,
    'session/set_config_option',
    ACP::Types::SetSessionConfigOptionRequest.new(
      session_id: 's1',
      config_id: 'thinking',
      value: ACP::Types::SetSessionConfigOptionRequest::Value::Boolean.new(value: true)
    ),
    { 'configOptions' => [] },
    ACP::Types::SetSessionConfigOptionResponse
  )

  it_sends(
    :authenticate,
    'authenticate',
    ACP::Types::AuthenticateRequest.new(method_id: 'token'),
    {},
    ACP::Types::AuthenticateResponse
  )

  it_sends(:logout, 'logout', ACP::Types::LogoutRequest.new, {}, ACP::Types::LogoutResponse)

  describe 'ext_request' do
    it 'refuses a name without the underscore prefix, before sending anything' do
      assert_equal(
        [ArgumentError, []],
        [assert_raises(ArgumentError) { connection.ext_request('myapp/double') }.class, @log]
      )
    end

    it 'sends the method with its params and returns the reply unparsed' do
      reply = { 'doubled' => 42 }
      @transport.replies['_myapp/double'] = reply
      answer = connection.ext_request('_myapp/double', { 'n' => 21 })

      assert_equal([[[:request, '_myapp/double', { 'n' => 21 }]], true], [@log, answer.equal?(reply)])
    end
  end

  describe 'cancelled?' do
    it 'is false when the transport is serving no request' do
      refute_predicate connection, :cancelled?
    end

    it 'is false while the request being served is not cancelled, whatever falsy answer it gives' do
      answers = [false, nil].map do |answer|
        @transport.cancellation = ClientConnectionCancellation.new(answer)
        connection.cancelled?
      end

      assert_equal [false, false], answers
    end

    it 'is true once the request being served is cancelled' do
      @transport.cancellation = ClientConnectionCancellation.new(true)

      assert_predicate connection, :cancelled?
    end
  end

  describe 'ext_notify' do
    it 'refuses a name without the underscore prefix, before sending anything' do
      assert_equal(
        [ArgumentError, []],
        [assert_raises(ArgumentError) { connection.ext_notify('myapp/tick') }.class, @log]
      )
    end

    it 'notifies the method with its params' do
      connection.ext_notify('_myapp/tick', { 'n' => 1 })

      assert_equal [[:notify, '_myapp/tick', { 'n' => 1 }]], @log
    end
  end

  describe 'mcp_message_notification' do
    it 'notifies mcp/message with the notification' do
      notification = ACP::Types::Unstable::MessageMcpNotification.new(
        server_id: 'srv_1', request_id: 'mcp_1', method: 'notifications/progress', params: { 'progress' => 1 }
      )
      connection.mcp_message_notification(notification)

      assert_equal [[:notify, 'mcp/message', notification.to_h]], @log
    end
  end

  describe 'parsing a reply' do
    def new_session
      connection.new_session(ACP::Types::NewSessionRequest.new(cwd: '/work', mcp_servers: []))
    end

    it "returns the agent's error" do
      error = ACP::RequestError.resource_not_found
      @transport.replies['session/new'] = error

      assert_same error, new_session
    end

    it 'answers a reply that does not parse with invalid response carrying the reply' do
      replies = [{}, [], nil]
      answers = replies.map do |reply|
        @transport.replies['session/new'] = reply
        new_session.to_h
      end

      assert_equal(replies.map { |reply| ACP::RequestError.invalid_response(reply).to_h }, answers)
    end
  end
end
