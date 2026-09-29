# frozen_string_literal: true

# Base class for the request and notification handlers Stdio dispatches to.
# Subclass it and override #call.
class ACP::Transport::Handler
  # @rbs params: untyped
  # @rbs return: ACP::Transport::Stdio::result
  def call(params)
    raise NotImplementedError, "#{self.class} must implement #call"
  end
end
