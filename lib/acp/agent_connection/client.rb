# frozen_string_literal: true

# The agent's handle on the connected client: session updates and permission
# requests go out through it, and it holds the capabilities the client
# declared in initialize.
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
    result = @peer.request('session/request_permission', request.to_h)
    result.error || ACP::Types::RequestPermissionResponse.from_h(result.value)
  end
end
