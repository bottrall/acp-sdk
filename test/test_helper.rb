# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/spec'
require 'acp/sdk'

# Collects what the code logs, one [severity, message] pair per report.
class FakeLogger
  def initialize
    @events = Thread::Queue.new
  end

  def warn(message)
    @events << [:warn, message]
  end

  def error(message)
    @events << [:error, message]
  end

  # Blocks up to timeout seconds, so tests can synchronize with the threads
  # that log.
  def pop(timeout = 2)
    @events.pop(timeout:)
  end

  # Returns everything logged so far, leaving nothing behind.
  def drain
    events = []
    events << @events.pop(true) until @events.empty?
    events
  rescue ThreadError
    events
  end
end
