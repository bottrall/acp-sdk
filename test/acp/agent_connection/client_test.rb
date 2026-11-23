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

  def advertising(peer, unstable: nil, **capabilities)
    before_initialize(peer).tap do |client|
      client.capabilities = ACP::Types::ClientCapabilities.new(**capabilities)
      client.unstable_capabilities = unstable
    end
  end

  def unadvertised(capability)
    ACP::RequestError.unadvertised(capability).to_h
  end

  let(:payload) { AgentConnectionClientMessage.new({ 'sessionId' => 's' }) }

  text = { 'type' => 'text', 'text' => 'hi' }
  session_content = [{ 'type' => 'session', 'sessionId' => 'child' }].freeze
  subagents = ACP::Types::SubagentCapabilities.new

  describe 'schema session update coverage' do
    ungated = %w[
      user_message_chunk
      agent_message_chunk
      agent_thought_chunk
      plan
      available_commands_update
      current_mode_update
      config_option_update
      session_info_update
      usage_update
    ].freeze
    gated = ACP::AgentConnection::Client::GATED_UPDATES.keys + ACP::AgentConnection::Client::SESSION_CONTENT_UPDATES
    listed = %w[schema.json schema.unstable.json].flat_map do |file|
      schema = JSON.parse(File.read(File.expand_path("../../../schema/#{file}", __dir__)))
      schema.dig('$defs', 'SessionUpdate', 'oneOf').map do |variant|
        variant.dig('properties', 'sessionUpdate', 'const')
      end
    end.uniq

    it 'gates every sessionUpdate variant schema/schema*.json lists, or lists it as ungated' do
      assert_empty(
        listed - gated - ungated,
        "gate these in ACP::AgentConnection::Client, or add them to the ungated list in #{__FILE__}"
      )
    end

    it 'lists as ungated only variants it does not gate' do
      assert_empty ungated & gated
    end

    it 'lists as ungated only variants schema/schema*.json lists' do
      assert_empty ungated - listed
    end
  end

  describe '#update' do
    def notified(update)
      [['session/update', ACP::Types::SessionNotification.new(session_id: 's', update:).to_h]]
    end

    plan = ACP::Types::PlanCapabilities.new
    stable_session = ACP::Types::ClientSessionCapabilities.new(notices: {}, compaction: {})
    unstable = lambda do |**session|
      ACP::Types::Unstable::ClientCapabilities.new(
        session: ACP::Types::Unstable::ClientSessionCapabilities.new(**session)
      )
    end
    prompt_suggestions = ACP::Types::Unstable::PromptSuggestionsCapabilities.new
    every_unstable = unstable.call(prompt_suggestions:, cursors: {})
    {
      'session.notices' => [
        { session: ACP::Types::ClientSessionCapabilities.new(notices: {}) },
        {
          session: ACP::Types::ClientSessionCapabilities.new(compaction: {}),
          plan:,
          subagents:,
          unstable: every_unstable
        },
        [{ 'sessionUpdate' => 'notice', 'severity' => 'info', 'title' => 'Heads up' }]
      ],
      'session.compaction' => [
        { session: ACP::Types::ClientSessionCapabilities.new(compaction: {}) },
        {
          session: ACP::Types::ClientSessionCapabilities.new(notices: {}),
          plan:,
          subagents:,
          unstable: every_unstable
        },
        [
          { 'sessionUpdate' => 'compaction_update', 'compactionId' => 'c', 'status' => 'started' },
          { 'sessionUpdate' => 'compaction_summary_chunk', 'compactionId' => 'c', 'content' => text }
        ]
      ],
      'plan' => [
        { plan: },
        { session: stable_session, subagents:, unstable: every_unstable },
        [
          {
            'sessionUpdate' => 'plan_update',
            'plan' => { 'planId' => 'p', 'type' => 'markdown', 'content' => '# Plan' }
          },
          { 'sessionUpdate' => 'plan_removed', 'planId' => 'p' }
        ]
      ],
      'session.promptSuggestions' => [
        { unstable: unstable.call(prompt_suggestions:) },
        { session: stable_session, plan:, subagents:, unstable: unstable.call(cursors: {}) },
        [{ 'sessionUpdate' => 'prompt_suggestions_update', 'suggestions' => [] }]
      ],
      'session.cursors' => [
        { unstable: unstable.call(cursors: {}) },
        { session: stable_session, plan:, subagents:, unstable: unstable.call(prompt_suggestions:) },
        [{ 'sessionUpdate' => 'cursor_update', 'cursorId' => 'c' }]
      ],
      'subagents' => [
        { subagents: },
        { session: stable_session, plan:, unstable: every_unstable },
        [
          { 'sessionUpdate' => 'subagent_update', 'sessionId' => 'child' },
          { 'sessionUpdate' => 'session_message', 'messageId' => 'm' },
          { 'sessionUpdate' => 'session_message_chunk', 'messageId' => 'm', 'content' => text },
          { 'sessionUpdate' => 'tool_call', 'toolCallId' => 't', 'title' => 'Delegate', 'content' => session_content },
          { 'sessionUpdate' => 'tool_call_update', 'toolCallId' => 't', 'content' => session_content }
        ],
        {
          'tool_call holding raw content' => ACP::Types::SessionUpdate::ToolCall.new(
            tool_call_id: 't', title: 'Delegate', content: session_content
          ),
          'tool_call_update holding raw content' => ACP::Types::SessionUpdate::ToolCallUpdate.new(
            tool_call_id: 't', content: session_content
          )
        }
      ]
    }.each do |capability, (advertised, others, hashes, built)|
      given = hashes.flat_map do |hash|
        types = [ACP::Types::SessionUpdate, ACP::Types::Unstable::SessionUpdate]
        [hash, *types.map { |type| type.from_h(hash) }].map do |update|
          ["#{hash['sessionUpdate']} given as #{update.class}", update]
        end
      end

      given.to_h.merge(built.to_h).each do |kind, update|
        it "refuses #{kind} without notifying unless the client advertised #{capability}" do
          peer = AgentConnectionClientPeer.new
          clients = [before_initialize(peer), advertising(peer), advertising(peer, **others)]

          assert_equal(
            [[unadvertised(capability)] * 3, []],
            [clients.map { |client| client.update('s', update).to_h }, peer.notifications]
          )
        end

        it "notifies #{kind} on a client that advertised #{capability}" do
          peer = AgentConnectionClientPeer.new
          advertising(peer, **advertised).update('s', update)

          assert_equal notified(update), peer.notifications
        end
      end
    end

    {
      'a tool call without content' => { 'sessionUpdate' => 'tool_call', 'toolCallId' => 't', 'title' => 'Read' },
      'a tool call with no session content' => {
        'sessionUpdate' => 'tool_call',
        'toolCallId' => 't',
        'title' => 'Read',
        'content' => [{ 'type' => 'content', 'content' => text }]
      },
      'a tool call update without content' => { 'sessionUpdate' => 'tool_call_update', 'toolCallId' => 't' },
      'a message chunk, whose content is one block' => { 'sessionUpdate' => 'agent_message_chunk', 'content' => text }
    }.each do |description, hash|
      it "notifies #{description} on a client that advertised nothing" do
        peer = AgentConnectionClientPeer.new
        update = ACP::Types::SessionUpdate.from_h(hash)
        advertising(peer).update('s', update)

        assert_equal notified(update), peer.notifications
      end
    end

    it 'notifies session/update with the update wrapped in a session notification' do
      peer = AgentConnectionClientPeer.new
      update = AgentConnectionClientMessage.new({ 'sessionUpdate' => 'custom' })
      before_initialize(peer).update('s', update)

      assert_equal notified(update), peer.notifications
    end

    it 'returns nil once it has notified' do
      update = AgentConnectionClientMessage.new({ 'sessionUpdate' => 'custom' })

      assert_nil before_initialize(AgentConnectionClientPeer.new).update('s', update)
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
    reply = { 'outcome' => { 'outcome' => 'cancelled' } }
    permission = lambda do |content|
      { 'sessionId' => 's', 'toolCall' => { 'toolCallId' => 't', 'content' => content }, 'options' => [] }
    end
    delegating = permission.call(session_content)
    {
      'a stable request' => ACP::Types::RequestPermissionRequest.from_h(delegating),
      'an unstable request' => ACP::Types::Unstable::RequestPermissionRequest.from_h(delegating),
      'a request holding raw content' => ACP::Types::RequestPermissionRequest.new(
        session_id: 's',
        tool_call: ACP::Types::ToolCallUpdate.new(tool_call_id: 't', content: session_content),
        options: []
      )
    }.each do |description, request|
      it "refuses #{description} with session content without a round trip unless the client advertised subagents" do
        peer = AgentConnectionClientPeer.new(reply)
        clients = [before_initialize(peer), advertising(peer), advertising(peer, terminal: true)]

        assert_equal(
          [[unadvertised('subagents')] * 3, []],
          [clients.map { |client| client.request_permission(request).to_h }, peer.requests]
        )
      end

      it "requests session/request_permission for #{description} with session content when subagents is advertised" do
        peer = AgentConnectionClientPeer.new(reply)
        response = advertising(peer, subagents:).request_permission(request)

        assert_equal(
          [ACP::Types::RequestPermissionResponse, [['session/request_permission', request.to_h]]],
          [response.class, peer.requests]
        )
      end
    end

    it 'requests session/request_permission without session content whatever the client advertised' do
      peer = AgentConnectionClientPeer.new(reply)
      content = [{ 'type' => 'content', 'content' => text }]
      request = ACP::Types::RequestPermissionRequest.from_h(permission.call(content))
      response = before_initialize(peer).request_permission(request)

      assert_equal(
        [ACP::Types::RequestPermissionResponse, [['session/request_permission', request.to_h]]],
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

  describe '#auth_status_update' do
    it 'refuses without notifying unless the agent advertised auth.status' do
      peer = AgentConnectionClientPeer.new
      error = before_initialize(peer).auth_status_update(payload)

      assert_equal [ACP::RequestError.unadvertised_agent('auth.status').to_h, []], [error.to_h, peer.notifications]
    end

    it 'notifies auth/status_update when the agent advertised auth.status' do
      peer = AgentConnectionClientPeer.new
      ACP::AgentConnection::Client.new(peer:, auth_status_advertised: true).auth_status_update(payload)

      assert_equal [['auth/status_update', payload.to_h]], peer.notifications
    end
  end

  describe '#ext_request' do
    it 'raises without a round trip for a name outside the extension namespace' do
      peer = AgentConnectionClientPeer.new
      client = before_initialize(peer)

      assert_equal(
        [ArgumentError, []],
        [raised(ArgumentError) { client.ext_request('session/prompt', {}) }.class, peer.requests]
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
        [raised(ArgumentError) { client.ext_notify('session/update', {}) }.class, peer.notifications]
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
