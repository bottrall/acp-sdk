# frozen_string_literal: true

class ACP::AgentConnection::Client
  # @rbs @peer: ACP::AgentConnection::_Peer

  # @dynamic capabilities, capabilities=
  attr_accessor :capabilities #: ACP::Types::ClientCapabilities?

  # @rbs peer: ACP::AgentConnection::_Peer
  # @rbs return: void
  def initialize(peer:)
    @peer = peer
    @capabilities = nil
  end

  # @rbs session_id: String
  # @rbs update: ACP::Types::SessionUpdate::t
  # @rbs return: void
  def update(session_id, update)
    @peer.notify('session/update', ACP::Types::SessionNotification.new(session_id:, update:).to_h)
  end

  # @rbs session_id: String
  # @rbs commands: Array[ACP::Types::AvailableCommand]
  # @rbs return: void
  def available_commands(session_id, commands)
    update(session_id, ACP::Types::SessionUpdate::AvailableCommandsUpdate.new(available_commands: commands))
  end

  # Blocks the calling thread until the client answers or the connection
  # closes.
  #
  # @rbs request: ACP::Types::RequestPermissionRequest
  # @rbs return: ACP::Types::RequestPermissionResponse | ACP::RequestError
  def request_permission(request)
    call('session/request_permission', ACP::Types::RequestPermissionResponse, request)
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
      return unadvertised('elicitation.form') unless capabilities&.elicitation&.form
    when ACP::Types::CreateElicitationRequest::Mode::Url
      return unadvertised('elicitation.url') unless capabilities&.elicitation&.url
    else
      return unadvertised("elicitation.#{request.mode['mode']}")
    end

    call('elicitation/create', ACP::Types::CreateElicitationResponse, request)
  end

  # @rbs notification: ACP::Types::CompleteElicitationNotification
  # @rbs return: void
  def complete_elicitation(notification)
    return unadvertised('elicitation.url') unless capabilities&.elicitation&.url

    @peer.notify('elicitation/complete', notification.to_h)
  end

  private

  # @rbs rpc_method: String
  # @rbs type: ACP::AgentConnection::_Parser
  # @rbs request: ACP::AgentConnection::_Response
  # @rbs return: untyped
  def call(rpc_method, type, request)
    result = @peer.request(rpc_method, request.to_h)
    return result if result.is_a?(ACP::RequestError)

    type.from_h(result)
  rescue KeyError, TypeError, NoMethodError
    ACP::RequestError.invalid_response(result)
  end

  # @rbs rpc_method: String
  # @rbs type: ACP::AgentConnection::_Parser
  # @rbs request: ACP::AgentConnection::_Response
  # @rbs return: untyped
  def terminal_call(rpc_method, type, request)
    return ACP::RequestError.unadvertised('terminal') unless capabilities&.terminal

    call(rpc_method, type, request)
  end
end
