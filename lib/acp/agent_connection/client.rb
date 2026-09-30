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
    return ACP::Transport::Stdio::METHOD_NOT_FOUND unless capabilities&.fs&.read_text_file

    call('fs/read_text_file', ACP::Types::ReadTextFileResponse, request)
  end

  # @rbs request: ACP::Types::WriteTextFileRequest
  # @rbs return: ACP::Types::WriteTextFileResponse | ACP::Transport::ResponseError
  def write_text_file(request)
    return ACP::Transport::Stdio::METHOD_NOT_FOUND unless capabilities&.fs&.write_text_file

    call('fs/write_text_file', ACP::Types::WriteTextFileResponse, request)
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
end
