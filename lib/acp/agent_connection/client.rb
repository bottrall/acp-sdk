# frozen_string_literal: true

class ACP::AgentConnection::Client
  # @rbs @peer: ACP::Transport::Stdio
  # @rbs @mcp_advertised: bool
  # @rbs @auth_status_advertised: bool

  GATED_UPDATES = {
    'notice' => %i[session notices].freeze,
    'compaction_update' => %i[session compaction].freeze,
    'compaction_summary_chunk' => %i[session compaction].freeze,
    'plan_update' => %i[plan].freeze,
    'plan_removed' => %i[plan].freeze,
    'prompt_suggestions_update' => %i[session prompt_suggestions].freeze,
    'cursor_update' => %i[session cursors].freeze,
    'subagent_update' => %i[subagents].freeze,
    'session_message' => %i[subagents].freeze,
    'session_message_chunk' => %i[subagents].freeze
  }.freeze #: Hash[String, Array[Symbol]]

  SESSION_CONTENT_UPDATES = %w[tool_call tool_call_update].freeze #: Array[String]
  SESSION_CONTENT_GATE = %i[subagents].freeze #: Array[Symbol]

  # @dynamic capabilities, capabilities=
  attr_accessor :capabilities #: ACP::Types::ClientCapabilities?

  # @dynamic unstable_capabilities=
  attr_writer :unstable_capabilities #: ACP::Types::Unstable::ClientCapabilities?

  # @rbs peer: ACP::Transport::Stdio
  # @rbs mcp_advertised: bool
  # @rbs auth_status_advertised: bool
  # @rbs return: void
  def initialize(peer:, mcp_advertised: false, auth_status_advertised: false)
    @peer = peer
    @mcp_advertised = mcp_advertised
    @auth_status_advertised = auth_status_advertised
    @capabilities = nil
    @unstable_capabilities = nil
  end

  # @rbs session_id: String
  # @rbs update: ACP::Types::SessionUpdate::t | ACP::Types::Unstable::SessionUpdate::t
  # @rbs return: ACP::RequestError?
  def update(session_id, update)
    wire = update.to_h
    kind = wire['sessionUpdate']
    gate = GATED_UPDATES.fetch(kind) { session_content_gate(wire['content']) if SESSION_CONTENT_UPDATES.include?(kind) }
    error = refusal(gate)
    return error if error

    @peer.notify('session/update', ACP::Types::SessionNotification.new(session_id:, update: wire).to_h)
    nil
  end

  # @rbs session_id: String
  # @rbs commands: Array[ACP::Types::AvailableCommand]
  # @rbs return: void
  def available_commands(session_id, commands)
    update(session_id, ACP::Types::SessionUpdate::AvailableCommandsUpdate.new(available_commands: commands))
  end

  # @rbs request: ACP::Types::RequestPermissionRequest
  # @rbs return: ACP::Types::RequestPermissionResponse | ACP::RequestError
  def request_permission(request)
    refusal(session_content_gate(request.to_h.dig('toolCall', 'content'))) ||
      call('session/request_permission', ACP::Types::RequestPermissionResponse, request)
  end

  # @rbs return: void
  def cancel_requests
    @peer.cancel_requests
  end

  # Always false off a handler thread.
  #
  # @rbs return: bool
  def cancelled?
    !!@peer.cancellation&.cancelled?
  end

  # @rbs request: ACP::Types::ReadTextFileRequest
  # @rbs return: ACP::Types::ReadTextFileResponse | ACP::RequestError
  def read_text_file(request)
    return ACP::RequestError.unadvertised('fs.readTextFile') unless capabilities&.fs&.read_text_file

    call('fs/read_text_file', ACP::Types::ReadTextFileResponse, request)
  end

  # @rbs request: ACP::Types::WriteTextFileRequest
  # @rbs return: ACP::Types::WriteTextFileResponse | ACP::RequestError
  def write_text_file(request)
    return ACP::RequestError.unadvertised('fs.writeTextFile') unless capabilities&.fs&.write_text_file

    call('fs/write_text_file', ACP::Types::WriteTextFileResponse, request)
  end

  # @rbs request: ACP::Types::CreateTerminalRequest
  # @rbs return: ACP::Types::CreateTerminalResponse | ACP::RequestError
  def create_terminal(request)
    terminal_call('terminal/create', ACP::Types::CreateTerminalResponse, request)
  end

  # @rbs request: ACP::Types::TerminalOutputRequest
  # @rbs return: ACP::Types::TerminalOutputResponse | ACP::RequestError
  def terminal_output(request)
    terminal_call('terminal/output', ACP::Types::TerminalOutputResponse, request)
  end

  # @rbs request: ACP::Types::WaitForTerminalExitRequest
  # @rbs return: ACP::Types::WaitForTerminalExitResponse | ACP::RequestError
  def wait_for_terminal_exit(request)
    terminal_call('terminal/wait_for_exit', ACP::Types::WaitForTerminalExitResponse, request)
  end

  # @rbs request: ACP::Types::KillTerminalRequest
  # @rbs return: ACP::Types::KillTerminalResponse | ACP::RequestError
  def kill_terminal(request)
    terminal_call('terminal/kill', ACP::Types::KillTerminalResponse, request)
  end

  # @rbs request: ACP::Types::ReleaseTerminalRequest
  # @rbs return: ACP::Types::ReleaseTerminalResponse | ACP::RequestError
  def release_terminal(request)
    terminal_call('terminal/release', ACP::Types::ReleaseTerminalResponse, request)
  end

  # @rbs request: ACP::Types::CreateElicitationRequest
  # @rbs return: ACP::Types::CreateElicitationResponse | ACP::RequestError
  def create_elicitation(request)
    case request.mode
    when ACP::Types::CreateElicitationRequest::Mode::Form
      return ACP::RequestError.unadvertised('elicitation.form') unless capabilities&.elicitation&.form
    when ACP::Types::CreateElicitationRequest::Mode::Url
      return ACP::RequestError.unadvertised('elicitation.url') unless capabilities&.elicitation&.url
    else
      return ACP::RequestError.unadvertised("elicitation.#{request.mode['mode']}")
    end

    call('elicitation/create', ACP::Types::CreateElicitationResponse, request)
  end

  # @rbs notification: ACP::Types::CompleteElicitationNotification
  # @rbs return: ACP::RequestError?
  def complete_elicitation(notification)
    return ACP::RequestError.unadvertised('elicitation.url') unless capabilities&.elicitation&.url

    @peer.notify('elicitation/complete', notification.to_h)
    nil
  end

  # @rbs request: ACP::Types::Unstable::MessageMcpRequest
  # @rbs return: (ACP::Types::Unstable::MessageMcpResponse::t | ACP::RequestError)
  def mcp_message(request)
    return ACP::RequestError.unadvertised_agent('mcpCapabilities.acp') unless @mcp_advertised

    call('mcp/message', ACP::Types::Unstable::MessageMcpResponse, request)
  end

  # @rbs notification: ACP::Types::Unstable::AuthStatusUpdateNotification
  # @rbs return: ACP::RequestError?
  def auth_status_update(notification)
    return ACP::RequestError.unadvertised_agent('auth.status') unless @auth_status_advertised

    @peer.notify('auth/status_update', notification.to_h)
    nil
  end

  # Extension methods have no schema to parse the result into.
  #
  # @rbs method: String
  # @rbs params: untyped
  # @rbs return: (Hash[String, untyped] | ACP::RequestError)
  def ext_request(method, params = nil)
    ACP::Extensions.validate_name(method)
    @peer.request(method, params)
  end

  # @rbs method: String
  # @rbs params: untyped
  # @rbs return: void
  def ext_notify(method, params = nil)
    ACP::Extensions.validate_name(method)
    @peer.notify(method, params)
  end

  private

  # @rbs content: Array[Hash[String, untyped]]?
  # @rbs return: Array[Symbol]?
  def session_content_gate(content)
    SESSION_CONTENT_GATE if content&.any? { |item| item['type'] == 'session' }
  end

  # @rbs path: Array[Symbol]?
  # @rbs return: ACP::RequestError?
  def refusal(path)
    return if path.nil? || [capabilities, @unstable_capabilities].any? { |root| ACP::Protocol.advertised?(root, path) }

    wire_names = path.map { |step| step.to_s.gsub(/_\w/) { |match| match.delete('_').upcase } }
    ACP::RequestError.unadvertised(wire_names.join('.'))
  end

  # @rbs rpc_method: String
  # @rbs type: ACP::Transport::_Parser
  # @rbs request: ACP::Transport::_Response
  # @rbs return: untyped
  def call(rpc_method, type, request)
    result = @peer.request(rpc_method, request.to_h)
    return result if result.is_a?(ACP::RequestError)

    response = ACP::Types.parse(type, result)
    response.is_a?(ACP::Types::ParseError) ? ACP::RequestError.invalid_response(result) : response
  end

  # @rbs rpc_method: String
  # @rbs type: ACP::Transport::_Parser
  # @rbs request: ACP::Transport::_Response
  # @rbs return: untyped
  def terminal_call(rpc_method, type, request)
    return ACP::RequestError.unadvertised('terminal') unless capabilities&.terminal

    call(rpc_method, type, request)
  end
end
