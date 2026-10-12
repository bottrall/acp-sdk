# frozen_string_literal: true

class ACP::Transport::Cancellation
  KEY = :acp_serving_cancellation #: Symbol

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
