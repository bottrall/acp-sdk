# frozen_string_literal: true

# The spec sanctions agents logging to stderr.
class ACP::Transport::StderrLogger
  # @rbs message: String
  # @rbs return: void
  def warn(message)
    Kernel.warn("acp: WARN: #{message}")
  end

  # @rbs message: String
  # @rbs return: void
  def error(message)
    Kernel.warn("acp: ERROR: #{message}")
  end
end
