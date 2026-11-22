# frozen_string_literal: true

class ACP::ClientConnection::AuthStatusUpdates
  # @rbs @handler: (^(ACP::Types::Unstable::AuthStatusUpdateNotification) -> void)?
  # @rbs @logger: ACP::Transport::_Logger
  # @rbs @advertised: bool

  # @dynamic advertised=
  attr_writer :advertised #: bool

  # @rbs handler: (^(ACP::Types::Unstable::AuthStatusUpdateNotification) -> void)?
  # @rbs logger: ACP::Transport::_Logger
  # @rbs return: void
  def initialize(handler:, logger:)
    @handler = handler
    @logger = logger
    @advertised = false
  end

  # @rbs return: Hash[String, ^(untyped) -> void]
  def notifications
    handler = @handler
    # The route references the unstable types, so it needs the caller's
    # `require 'acp/types/unstable'`.
    return {} unless handler && ACP::Types.unstable_enabled?

    { 'auth/status_update' => ->(params) { update(handler, params) } }
  end

  private

  # @rbs handler: ^(ACP::Types::Unstable::AuthStatusUpdateNotification) -> void
  # @rbs params: untyped
  # @rbs return: void
  def update(handler, params)
    # A notification has no reply to carry a refusal, so one the agent did not
    # advertise is dropped.
    return unless @advertised

    notification = ACP::Types.parse(ACP::Types::Unstable::AuthStatusUpdateNotification, params)
    if notification.is_a?(ACP::Types::ParseError)
      @logger.warn("dropped malformed auth/status_update: #{notification.message}")
    else
      handler.call(notification)
    end
  end
end
