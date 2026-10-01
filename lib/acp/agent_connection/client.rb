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
  # @rbs return: ACP::Types::RequestPermissionResponse | ACP::Transport::ResponseError
  def request_permission(request)
    call('session/request_permission', ACP::Types::RequestPermissionResponse, request)
  end

  # @rbs request: ACP::Types::ReadTextFileRequest
  # @rbs return: ACP::Types::ReadTextFileResponse | ACP::Transport::ResponseError
  def read_text_file(request)
    return unadvertised('fs.readTextFile') unless capabilities&.fs&.read_text_file

    call('fs/read_text_file', ACP::Types::ReadTextFileResponse, request)
  end

  # @rbs request: ACP::Types::WriteTextFileRequest
  # @rbs return: ACP::Types::WriteTextFileResponse | ACP::Transport::ResponseError
  def write_text_file(request)
    return unadvertised('fs.writeTextFile') unless capabilities&.fs&.write_text_file

    call('fs/write_text_file', ACP::Types::WriteTextFileResponse, request)
  end

  # @rbs request: ACP::Types::CreateTerminalRequest
  # @rbs return: ACP::Types::CreateTerminalResponse | ACP::Transport::ResponseError
  def create_terminal(request)
    terminal_call('terminal/create', ACP::Types::CreateTerminalResponse, request)
  end

  # @rbs request: ACP::Types::TerminalOutputRequest
  # @rbs return: ACP::Types::TerminalOutputResponse | ACP::Transport::ResponseError
  def terminal_output(request)
    terminal_call('terminal/output', ACP::Types::TerminalOutputResponse, request)
  end

  # @rbs request: ACP::Types::WaitForTerminalExitRequest
  # @rbs return: ACP::Types::WaitForTerminalExitResponse | ACP::Transport::ResponseError
  def wait_for_terminal_exit(request)
    terminal_call('terminal/wait_for_exit', ACP::Types::WaitForTerminalExitResponse, request)
  end

  # @rbs request: ACP::Types::KillTerminalRequest
  # @rbs return: ACP::Types::KillTerminalResponse | ACP::Transport::ResponseError
  def kill_terminal(request)
    terminal_call('terminal/kill', ACP::Types::KillTerminalResponse, request)
  end

  # @rbs request: ACP::Types::ReleaseTerminalRequest
  # @rbs return: ACP::Types::ReleaseTerminalResponse | ACP::Transport::ResponseError
  def release_terminal(request)
    terminal_call('terminal/release', ACP::Types::ReleaseTerminalResponse, request)
  end

  private

  # @rbs rpc_method: String
  # @rbs type: ACP::AgentConnection::_Parser
  # @rbs request: ACP::AgentConnection::_Response
  # @rbs return: untyped
  def call(rpc_method, type, request)
    result = @peer.request(rpc_method, request.to_h)
    result.error || type.from_h(result.value)
  end

  # @rbs rpc_method: String
  # @rbs type: ACP::AgentConnection::_Parser
  # @rbs request: ACP::AgentConnection::_Response
  # @rbs return: untyped
  def terminal_call(rpc_method, type, request)
    return unadvertised('terminal') unless capabilities&.terminal

    call(rpc_method, type, request)
  end

  # Same method-not-found code a peer would send, but with a message that says
  # the refusal was local, so logs can tell the two cases apart.
  #
  # @rbs capability: String
  # @rbs return: ACP::Transport::ResponseError
  def unadvertised(capability)
    ACP::Transport::ResponseError.new(
      code: ACP::RequestError::METHOD_NOT_FOUND, message: "Client does not advertise #{capability}"
    )
  end
end
