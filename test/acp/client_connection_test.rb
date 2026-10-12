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

  def complete_elicitation(params)
    @log << [:complete_elicitation, params]
  end

  def cancel(session_id)
    @log << [:cancel, session_id]
  end

  def register_elicitation(elicitation_id)
    @log << [:register_elicitation, elicitation_id]
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
  end

  def connection(**)
    ACP::ClientConnection.new(transport: @transport, permission: ->(_request) {}, streams: @streams, **)
  end

  def started(**)
    connection(**).tap(&:start)
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

  def recording(name, answer = nil)
    lambda do |request|
      @log << [name, request.class]
      answer
    end
  end

  def serve_handlers(answer = nil)
    %i[
      read_text_file
      write_text_file
      create_terminal
      terminal_output
      wait_for_terminal_exit
      kill_terminal
      release_terminal
    ].to_h { |name| [name, recording(name, answer)] }
  end

  def parse_error(type, params)
    type.from_h(params)
  rescue ACP::Types::ParseError => e
    e
  end

  def self.it_sends(method, wire, request, reply, response)
    it "sends #{wire} with the request and parses the reply as #{response.name}" do
      @transport.replies[wire] = reply
      answer = connection.public_send(method, request)

      assert_equal([[[:request, wire, request.to_h]], response], [@log, answer.class])
    end
  end

  describe ACP::ClientConnection::Route do
    def build(**)
      ACP::ClientConnection::Route.new(
        wire: 'x/y', type: ACP::Types::ReadTextFileRequest, handler: :@x, family: :@y, key: 'x.y', **
      )
    end

    it 'labels a route with its key when no label is given' do
      assert_equal 'x.y', build.label
    end

    it 'keeps a label that differs from the key' do
      assert_equal %w[x.y x.create], [build(label: 'x.create').key, build(label: 'x.create').label]
    end
  end

  describe 'initialize' do
    it 'refuses an extension request name without the underscore prefix' do
      assert_raises(ArgumentError) { connection(extension_requests: { 'myapp/ping' => ->(_params) {} }) }
    end

    it 'refuses an extension notification name without the underscore prefix' do
      assert_raises(ArgumentError) { connection(extension_notifications: { 'myapp/note' => ->(_params) {} }) }
    end
  end

  describe 'start' do
    it "returns the transport's reader thread" do
      assert_same @transport.reader, connection.start
    end

    it 'routes session/request_permission to the streams' do
      started
      answer = route('session/request_permission').call(:params)

      assert_equal([[%i[request_permission params]], :permission_answer], [@log, answer])
    end

    it 'routes the extension requests to their handlers' do
      handler = ->(_params) {}
      started(extension_requests: { '_myapp/ping' => handler })

      assert_same handler, route('_myapp/ping')
    end

    it 'routes session/update and elicitation/complete to the streams' do
      started
      @transport.notification_handlers.fetch('session/update').call(:update)
      @transport.notification_handlers.fetch('elicitation/complete').call(:completion)

      assert_equal [%i[dispatch update], %i[complete_elicitation completion]], @log
    end

    it 'routes the extension notifications to their handlers' do
      handler = ->(_params) {}
      started(extension_notifications: { '_myapp/note' => handler })

      assert_same handler, @transport.notification_handlers.fetch('_myapp/note')
    end
  end

  describe 'connect' do
    def refusal(connection, request)
      [assert_raises(ArgumentError) { connection.connect(request) }.message, @log]
    end

    it 'refuses to advertise an fs method no handler serves, before sending anything' do
      client = connection(read_text_file: ->(_request) {})
      request = initialize_request(fs: fs(read_text_file: true, write_text_file: true))

      assert_equal(
        ['initialize advertises fs methods no handler serves: fs.writeTextFile', []],
        refusal(client, request)
      )
    end

    it 'names only the fs methods the request advertises' do
      request = initialize_request(fs: fs(read_text_file: true), terminal: true)

      assert_equal(
        ['initialize advertises fs methods no handler serves: fs.readTextFile', []],
        refusal(connection, request)
      )
    end

    it 'refuses to advertise the terminal when a terminal method has no handler' do
      client = connection(create_terminal: ->(_request) {})
      expected = 'initialize advertises terminal methods no handler serves: ' \
                 'terminal.output, terminal.wait_for_exit, terminal.kill, terminal.release'

      assert_equal [expected, []], refusal(client, initialize_request(terminal: true))
    end

    it 'refuses to advertise the form elicitation mode with no elicitation handler' do
      assert_equal(
        ['initialize advertises elicitation modes no handler serves: elicitation.form', []],
        refusal(connection, initialize_request(elicitation: modes(:form)))
      )
    end

    it 'refuses to advertise the url elicitation mode with no elicitation handler' do
      assert_equal(
        ['initialize advertises elicitation modes no handler serves: elicitation.url', []],
        refusal(connection, initialize_request(elicitation: modes(:url)))
      )
    end

    it 'advertises every capability its handlers serve' do
      client = connection(**serve_handlers, elicitation: ->(_request) {})
      request = initialize_request(
        fs: fs(read_text_file: true, write_text_file: true), terminal: true, elicitation: modes(:form, :url)
      )

      assert_instance_of ACP::Types::InitializeResponse, client.connect(request)
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

      assert_equal([[[:request, 'initialize', request.to_h]], ACP::Types::InitializeResponse], [@log, answer.class])
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

  describe 'serving a route' do
    terminal_params = { 'sessionId' => 's', 'terminalId' => 't1' }
    routes = [
      [
        'fs/read_text_file',
        :read_text_file,
        'fs.readTextFile',
        { 'sessionId' => 's', 'path' => '/a.txt' },
        ACP::Types::ReadTextFileRequest
      ],
      [
        'fs/write_text_file',
        :write_text_file,
        'fs.writeTextFile',
        { 'sessionId' => 's', 'path' => '/a.txt', 'content' => 'hi' },
        ACP::Types::WriteTextFileRequest
      ],
      [
        'terminal/create',
        :create_terminal,
        'terminal',
        { 'sessionId' => 's', 'command' => 'echo' },
        ACP::Types::CreateTerminalRequest
      ],
      ['terminal/output', :terminal_output, 'terminal', terminal_params, ACP::Types::TerminalOutputRequest],
      [
        'terminal/wait_for_exit',
        :wait_for_terminal_exit,
        'terminal',
        terminal_params,
        ACP::Types::WaitForTerminalExitRequest
      ],
      ['terminal/kill', :kill_terminal, 'terminal', terminal_params, ACP::Types::KillTerminalRequest],
      ['terminal/release', :release_terminal, 'terminal', terminal_params, ACP::Types::ReleaseTerminalRequest]
    ]

    def advertising(**capabilities)
      started(**serve_handlers(:answer)).tap do |client|
        client.connect(initialize_request(**capabilities))
        @log.clear
      end
    end

    def advertising_everything
      advertising(fs: fs(read_text_file: true, write_text_file: true), terminal: true)
    end

    routes.each do |wire, _handler, key, params, _type|
      it "refuses #{wire} as unadvertised #{key} before connect records the capabilities" do
        started(**serve_handlers)
        reply = route(wire).call(params)

        assert_equal([ACP::RequestError.unadvertised(key).to_h, []], [reply.to_h, @log])
      end
    end

    it 'refuses fs/read_text_file when connect advertised only fs/write_text_file' do
      advertising(fs: fs(write_text_file: true))
      reply = route('fs/read_text_file').call({ 'sessionId' => 's', 'path' => '/a.txt' })

      assert_equal([ACP::RequestError.unadvertised('fs.readTextFile').to_h, []], [reply.to_h, @log])
    end

    it 'refuses fs/write_text_file when connect advertised only fs/read_text_file' do
      advertising(fs: fs(read_text_file: true))
      reply = route('fs/write_text_file').call({ 'sessionId' => 's', 'path' => '/a.txt', 'content' => 'hi' })

      assert_equal([ACP::RequestError.unadvertised('fs.writeTextFile').to_h, []], [reply.to_h, @log])
    end

    it 'answers params that fail to parse with invalid params carrying the parse error, without calling the handler' do
      advertising_everything
      reply = route('fs/read_text_file').call({})
      error = parse_error(ACP::Types::ReadTextFileRequest, {})

      assert_equal([ACP::RequestError.invalid_params([error.message]).to_h, []], [reply.to_h, @log])
    end

    it 'answers params of the wrong shape with bare invalid params, without calling the handler' do
      advertising_everything
      replies = [nil, []].map { |params| route('fs/read_text_file').call(params).to_h }

      assert_equal([[ACP::RequestError.invalid_params.to_h] * 2, []], [replies, @log])
    end

    routes.each do |wire, handler, _key, params, type|
      it "parses #{wire} as #{type.name} for the #{handler} handler and returns its answer" do
        advertising_everything
        reply = route(wire).call(params)

        assert_equal([:answer, [[handler, type]]], [reply, @log])
      end
    end
  end

  describe 'the mcp/message route' do
    def mcp_params
      { 'serverId' => 'srv_1', 'requestId' => 'mcp_1', 'method' => 'tools/call', 'params' => { 'name' => 'echo' } }
    end

    it 'is not registered without an mcp_message handler' do
      started

      refute_includes @transport.handlers.keys, 'mcp/message'
    end

    it 'is not registered when the unstable types are not loaded' do
      out, _err = Open3.capture3('bundle', 'exec', 'ruby', '-I', 'lib', '-e', <<~RUBY)
        require 'acp/sdk'

        transport = Class.new do
          attr_reader :requests

          def start(requests:, notifications:)
            @requests = requests
          end
        end.new
        ACP::ClientConnection.new(transport:, permission: ->(_request) {}, mcp_message: ->(_request) {}).start
        print transport.requests.key?('mcp/message')
      RUBY

      assert_equal 'false', out
    end

    it 'refuses as unadvertised by the agent before connect records its advertisement' do
      started(mcp_message: recording(:mcp_message))
      reply = route('mcp/message').call(mcp_params)

      assert_equal([ACP::RequestError.unadvertised_agent('mcpCapabilities.acp').to_h, []], [reply.to_h, @log])
    end

    it 'refuses when the initialize reply carries no agent capabilities' do
      started(mcp_message: recording(:mcp_message)).connect(initialize_request)
      @log.clear
      reply = route('mcp/message').call(mcp_params)

      assert_equal([ACP::RequestError.unadvertised_agent('mcpCapabilities.acp').to_h, []], [reply.to_h, @log])
    end

    it 'parses the request for the mcp_message handler once the initialize reply advertises mcpCapabilities.acp' do
      @transport.replies['initialize'] = {
        'protocolVersion' => 1, 'agentCapabilities' => { 'mcpCapabilities' => { 'acp' => true } }
      }
      started(mcp_message: recording(:mcp_message, :answer)).connect(initialize_request)
      @log.clear
      reply = route('mcp/message').call(mcp_params)

      assert_equal([:answer, [[:mcp_message, ACP::Types::Unstable::MessageMcpRequest]]], [reply, @log])
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

  describe 'the elicitation/create route' do
    def form_params
      {
        'sessionId' => 's', 'mode' => 'form', 'message' => 'Pick one',
        'requestedSchema' => { 'type' => 'object', 'properties' => {} }
      }
    end

    def url_params
      {
        'sessionId' => 's', 'mode' => 'url', 'elicitationId' => 'e1',
        'url' => 'https://example.com/connect', 'message' => 'Authorize access'
      }
    end

    def advertising(*names)
      started(elicitation: recording(:elicitation, :answer)).tap do |client|
        client.connect(initialize_request(elicitation: modes(*names)))
        @log.clear
      end
    end

    it 'answers params of the wrong shape with invalid params, without calling the handler' do
      advertising(:form, :url)
      replies = [nil, []].map { |params| route('elicitation/create').call(params).to_h }

      assert_equal([[ACP::RequestError.invalid_params.to_h] * 2, []], [replies, @log])
    end

    it 'refuses a form request before connect records the capabilities' do
      started(elicitation: recording(:elicitation))
      reply = route('elicitation/create').call(form_params)

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.form').to_h, []], [reply.to_h, @log])
    end

    it 'refuses a form request when connect advertised only the url mode' do
      advertising(:url)
      reply = route('elicitation/create').call(form_params)

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.form').to_h, []], [reply.to_h, @log])
    end

    it 'refuses a url request before connect records the capabilities, without registering it' do
      started(elicitation: recording(:elicitation))
      reply = route('elicitation/create').call(url_params)

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.url').to_h, []], [reply.to_h, @log])
    end

    it 'refuses a url request when connect advertised only the form mode, without registering it' do
      advertising(:form)
      reply = route('elicitation/create').call(url_params)

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.url').to_h, []], [reply.to_h, @log])
    end

    it 'refuses a mode it does not know, naming the mode' do
      advertising(:form, :url)
      reply = route('elicitation/create').call({ 'sessionId' => 's', 'mode' => 'other', 'message' => 'hi' })

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.other').to_h, []], [reply.to_h, @log])
    end

    it 'hands an advertised form request to the elicitation handler and returns its answer' do
      advertising(:form)
      reply = route('elicitation/create').call(form_params)

      assert_equal([:answer, [[:elicitation, ACP::Types::CreateElicitationRequest]]], [reply, @log])
    end

    it 'registers an advertised url request for completion before handing it to the elicitation handler' do
      advertising(:url)
      reply = route('elicitation/create').call(url_params)

      assert_equal(
        [:answer, [[:register_elicitation, 'e1'], [:elicitation, ACP::Types::CreateElicitationRequest]]],
        [reply, @log]
      )
    end
  end
end
