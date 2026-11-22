# frozen_string_literal: true

require 'test_helper'
require 'open3'

require 'acp/types/unstable'

class InboundElicitations
  def initialize(log)
    @log = log
  end

  def register(elicitation_id)
    @log << [:register, elicitation_id]
  end

  def complete(params)
    @log << [:complete, params]
  end
end

describe ACP::ClientConnection::Inbound do
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
    ['terminal/create', :create_terminal, 'terminal', { 'sessionId' => 's', 'command' => 'echo' },
     ACP::Types::CreateTerminalRequest],
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
  ].freeze
  before do
    @log = []
    @elicitations = InboundElicitations.new(@log)
  end

  def inbound(**)
    ACP::ClientConnection::Inbound.new(elicitations: @elicitations, **)
  end

  def fs_methods
    %i[read_text_file write_text_file]
  end

  def terminal_methods
    %i[create_terminal terminal_output wait_for_terminal_exit kill_terminal release_terminal]
  end

  def recorder(*methods, answer: :answer)
    log = @log
    Object.new.tap do |object|
      methods.each do |name|
        object.define_singleton_method(name) do |request|
          log << [name, request.class]
          answer
        end
      end
    end
  end

  def capabilities(**)
    ACP::Types::ClientCapabilities.new(**)
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

  def everything
    capabilities(fs: fs(read_text_file: true, write_text_file: true), terminal: true)
  end

  def serving_everything
    served = inbound(fs: recorder(*fs_methods), terminal: recorder(*terminal_methods))
    served.advertise(everything)
    served
  end

  def refusal(served, advertised)
    assert_raises(ArgumentError) { served.advertise(advertised) }.message
  end

  describe '#initialize' do
    it 'refuses an extension request name without the underscore prefix' do
      assert_raises(ArgumentError) { inbound(extension_requests: { 'myapp/ping' => ->(_params) {} }) }
    end

    it 'refuses an extension notification name without the underscore prefix' do
      assert_raises(ArgumentError) { inbound(extension_notifications: { 'myapp/note' => ->(_params) {} }) }
    end
  end

  describe '#requests' do
    it 'routes the fs, terminal and elicitation methods' do
      assert_equal [*routes.map(&:first), 'elicitation/create'].sort, inbound.requests.keys.sort
    end

    it 'adds the extension requests' do
      handler = ->(_params) {}

      assert_same handler, inbound(extension_requests: { '_myapp/ping' => handler }).requests['_myapp/ping']
    end
  end

  describe '#notifications' do
    it 'routes elicitation/complete to the elicitations' do
      inbound.notifications.fetch('elicitation/complete').call(:completion)

      assert_equal [%i[complete completion]], @log
    end

    it 'adds the extension notifications' do
      handler = ->(_params) {}

      assert_same handler, inbound(extension_notifications: { '_myapp/note' => handler }).notifications['_myapp/note']
    end
  end

  describe '#advertise' do
    it 'refuses an advertised fs method its handler does not serve' do
      served = inbound(fs: recorder(:read_text_file))

      assert_equal(
        'initialize advertises fs methods no handler serves: write_text_file',
        refusal(served, capabilities(fs: fs(read_text_file: true, write_text_file: true)))
      )
    end

    it 'names only the fs methods the capabilities advertise' do
      assert_equal(
        'initialize advertises fs methods no handler serves: read_text_file',
        refusal(inbound, capabilities(fs: fs(read_text_file: true)))
      )
    end

    it 'refuses to advertise the terminal when a terminal method has no handler' do
      assert_equal(
        'initialize advertises terminal methods no handler serves: ' \
        'terminal_output, wait_for_terminal_exit, kill_terminal, release_terminal',
        refusal(inbound(terminal: recorder(:create_terminal)), capabilities(terminal: true))
      )
    end

    it 'refuses to advertise the form elicitation mode with no elicitation handler' do
      assert_equal(
        'initialize advertises elicitation modes no handler serves: elicitation.form',
        refusal(inbound, capabilities(elicitation: modes(:form)))
      )
    end

    it 'refuses to advertise the url elicitation mode with no elicitation handler' do
      assert_equal(
        'initialize advertises elicitation modes no handler serves: elicitation.url',
        refusal(inbound(elicitation: Object.new), capabilities(elicitation: modes(:url)))
      )
    end

    it 'accepts a client that advertises no capabilities, whose routes keep refusing' do
      served = inbound(fs: recorder(*fs_methods))
      served.advertise(nil)
      reply = served.requests.fetch('fs/read_text_file').call({ 'sessionId' => 's', 'path' => '/a.txt' })

      assert_equal [ACP::RequestError.unadvertised('fs.readTextFile').to_h, []], [reply.to_h, @log]
    end

    it 'records nothing when it refuses' do
      served = inbound(fs: recorder(*fs_methods))
      refusal(served, capabilities(fs: fs(read_text_file: true), terminal: true))
      reply = served.requests.fetch('fs/read_text_file').call({ 'sessionId' => 's', 'path' => '/a.txt' })

      assert_equal [ACP::RequestError.unadvertised('fs.readTextFile').to_h, []], [reply.to_h, @log]
    end

    it 'records every capability its handlers serve, so their routes serve' do
      served = inbound(
        fs: recorder(*fs_methods), terminal: recorder(*terminal_methods), elicitation: recorder(:create_elicitation)
      )
      served.advertise(
        capabilities(
          fs: fs(read_text_file: true, write_text_file: true), terminal: true, elicitation: modes(:form, :url)
        )
      )
      reply = served.requests.fetch('terminal/kill').call(terminal_params)

      assert_equal [:answer, [[:kill_terminal, ACP::Types::KillTerminalRequest]]], [reply, @log]
    end
  end

  describe 'serving an fs or terminal route' do
    routes.each do |wire, _handler, key, params, _type|
      it "refuses #{wire} as unadvertised #{key} before the capabilities are advertised" do
        served = inbound(fs: recorder(*fs_methods), terminal: recorder(*terminal_methods))
        reply = served.requests.fetch(wire).call(params)

        assert_equal([ACP::RequestError.unadvertised(key).to_h, []], [reply.to_h, @log])
      end
    end

    it 'refuses fs/read_text_file when only fs/write_text_file was advertised' do
      served = inbound(fs: recorder(*fs_methods))
      served.advertise(capabilities(fs: fs(write_text_file: true)))
      reply = served.requests.fetch('fs/read_text_file').call({ 'sessionId' => 's', 'path' => '/a.txt' })

      assert_equal([ACP::RequestError.unadvertised('fs.readTextFile').to_h, []], [reply.to_h, @log])
    end

    it 'answers params that fail to parse with invalid params carrying the parse error, without calling the handler' do
      reply = serving_everything.requests.fetch('fs/read_text_file').call({})
      error = ACP::Types.parse(ACP::Types::ReadTextFileRequest, {})

      assert_equal([ACP::RequestError.invalid_params([error.message]).to_h, []], [reply.to_h, @log])
    end

    routes.each do |wire, handler, _key, params, type|
      it "parses #{wire} as #{type.name} for the handler's #{handler} and returns its answer" do
        reply = serving_everything.requests.fetch(wire).call(params)

        assert_equal([:answer, [[handler, type]]], [reply, @log])
      end
    end
  end

  describe 'the mcp/message route' do
    def mcp_params
      { 'serverId' => 'srv_1', 'requestId' => 'mcp_1', 'method' => 'tools/call', 'params' => { 'name' => 'echo' } }
    end

    def mcp_handler
      log = @log
      lambda do |request|
        log << [:mcp_message, request.class]
        :answer
      end
    end

    it 'is not registered without an mcp_message handler' do
      refute_includes inbound.requests.keys, 'mcp/message'
    end

    it 'is not registered when the unstable types are not loaded' do
      out, _err = Open3.capture3('bundle', 'exec', 'ruby', '-I', 'lib', '-e', <<~RUBY)
        require 'acp/sdk'

        inbound = ACP::ClientConnection::Inbound.new(elicitations: nil, mcp_message: ->(_request) {})
        print inbound.requests.key?('mcp/message')
      RUBY

      assert_equal 'false', out
    end

    it 'refuses as unadvertised by the agent until the agent advertises mcpCapabilities.acp' do
      reply = inbound(mcp_message: mcp_handler).requests.fetch('mcp/message').call(mcp_params)

      assert_equal([ACP::RequestError.unadvertised_agent('mcpCapabilities.acp').to_h, []], [reply.to_h, @log])
    end

    it 'parses the request for the mcp_message handler once the agent advertises mcpCapabilities.acp' do
      served = inbound(mcp_message: mcp_handler)
      served.mcp_advertised = true
      reply = served.requests.fetch('mcp/message').call(mcp_params)

      assert_equal([:answer, [[:mcp_message, ACP::Types::Unstable::MessageMcpRequest]]], [reply, @log])
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
      inbound(elicitation: recorder(:create_elicitation)).tap do |served|
        served.advertise(capabilities(elicitation: modes(*names))) unless names.empty?
      end
    end

    def create(served, params)
      served.requests.fetch('elicitation/create').call(params)
    end

    it 'answers params that fail to parse with invalid params carrying the parse error, without calling the handler' do
      reply = create(advertising(:form, :url), {})
      error = ACP::Types.parse(ACP::Types::CreateElicitationRequest, {})

      assert_equal([ACP::RequestError.invalid_params([error.message]).to_h, []], [reply.to_h, @log])
    end

    it 'refuses a form request before the capabilities are advertised' do
      reply = create(advertising, form_params)

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.form').to_h, []], [reply.to_h, @log])
    end

    it 'refuses a form request when only the url mode was advertised' do
      reply = create(advertising(:url), form_params)

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.form').to_h, []], [reply.to_h, @log])
    end

    it 'refuses a url request before the capabilities are advertised, without registering it' do
      reply = create(advertising, url_params)

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.url').to_h, []], [reply.to_h, @log])
    end

    it 'refuses a url request when only the form mode was advertised, without registering it' do
      reply = create(advertising(:form), url_params)

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.url').to_h, []], [reply.to_h, @log])
    end

    it 'refuses a mode it does not know, naming the mode' do
      reply = create(advertising(:form, :url), { 'sessionId' => 's', 'mode' => 'other', 'message' => 'hi' })

      assert_equal([ACP::RequestError.unadvertised_mode('elicitation.other').to_h, []], [reply.to_h, @log])
    end

    it 'hands an advertised form request to the elicitation handler and returns its answer' do
      reply = create(advertising(:form), form_params)

      assert_equal([:answer, [[:create_elicitation, ACP::Types::CreateElicitationRequest]]], [reply, @log])
    end

    it 'registers an advertised url request for completion before handing it to the elicitation handler' do
      reply = create(advertising(:url), url_params)

      assert_equal(
        [:answer, [[:register, 'e1'], [:create_elicitation, ACP::Types::CreateElicitationRequest]]],
        [reply, @log]
      )
    end
  end
end
