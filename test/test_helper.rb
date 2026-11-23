# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/spec'
require 'json'
require 'acp/sdk'

SCHEMA_METHODS = %w[meta.json meta.unstable.json]
                 .map { |file| JSON.parse(File.read(File.expand_path("../schema/#{file}", __dir__))) }
                 .flat_map { |meta| meta.select { |_, methods| methods.is_a?(Hash) }.to_a }
                 .group_by(&:first)
                 .transform_values { |sections| sections.flat_map { |_, methods| methods.values }.uniq }
                 .freeze

# Each section's coverage lives in the test file of the side that handles it,
# so a section upstream adds would otherwise go unchecked.
unless (SCHEMA_METHODS.keys - %w[agentMethods clientMethods protocolMethods proxyMethods]).empty?
  raise "schema/meta*.json adds a section; cover it in the connection or transport tests: #{SCHEMA_METHODS.keys}"
end

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
