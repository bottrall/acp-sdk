# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/spec'
require 'json'
require 'acp/sdk'
require_relative '../codegen/schema_diff'

SCHEMA_METHODS = %w[meta.json meta.unstable.json]
                 .map { |file| JSON.parse(File.read(File.expand_path("../schema/#{file}", __dir__))) }
                 .map { |meta| SchemaDiff.methods_by_section(meta) }
                 .reduce { |all, meta| all.merge(meta) { |_section, stable, unstable| stable | unstable } }
                 .freeze

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

  # Lets tests synchronize with the threads that log.
  def pop(timeout = 2)
    @events.pop(timeout:)
  end

  def drain
    events = []
    events << @events.pop(true) until @events.empty?
    events
  rescue ThreadError
    events
  end
end

module RaisedError
  # The `klass` error the block raises, or nil when it returns, so a test can
  # check an error in the same one assertion as its other outcomes.
  def raised(klass)
    yield
    nil
  rescue klass => e
    e
  end
end

Minitest::Test.include(RaisedError)
