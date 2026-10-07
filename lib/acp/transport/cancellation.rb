# frozen_string_literal: true

# Whether the peer cancelled one request. The transport creates one per served
# request, marks it when the peer's $/cancel_request arrives, and hands it to
# the serving thread, whose handler can observe it and end the request early.
class ACP::Transport::Cancellation
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
