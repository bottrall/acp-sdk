# frozen_string_literal: true

# Whether the peer cancelled one request. The transport creates one per served
# request, marks it when the peer's $/cancel_request arrives, and hands it to
# the serving thread, whose handler can observe it and end the request early.
class ACP::Transport::Cancellation
  KEY = :acp_serving_cancellation #: Symbol

  # Connections read this to expose the serving state to their handlers and
  # write it to carry serving identity onto a thread they spawn; nil off a
  # serve thread.
  #
  # @rbs return: ACP::Transport::Cancellation?
  def self.current
    Thread.current[KEY] #: ACP::Transport::Cancellation?
  end

  # @rbs cancellation: ACP::Transport::Cancellation?
  # @rbs return: void
  def self.current=(cancellation)
    Thread.current[KEY] = cancellation
  end

  # @rbs @lock: Thread::Mutex
  # @rbs @cancelled: bool

  # @rbs return: void
  def initialize
    @lock = Mutex.new
    @cancelled = false
  end

  # @rbs return: void
  def cancel
    @lock.synchronize { @cancelled = true }
  end

  # @rbs return: bool
  def cancelled?
    @lock.synchronize { @cancelled }
  end
end
