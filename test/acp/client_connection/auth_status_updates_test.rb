# frozen_string_literal: true

require 'test_helper'
require 'open3'

require 'acp/types/unstable'

describe ACP::ClientConnection::AuthStatusUpdates do
  before do
    @log = []
    @logger = FakeLogger.new
  end

  def status_params
    { 'state' => 'authenticated' }
  end

  def status_handler
    log = @log
    ->(notification) { log << [:auth_status_update, notification.class] }
  end

  def updates(handler = status_handler)
    ACP::ClientConnection::AuthStatusUpdates.new(handler:, logger: @logger)
  end

  def advertised
    updates.tap { |served| served.advertised = true }
  end

  def deliver(served, params)
    served.notifications.fetch('auth/status_update').call(params)
  end

  describe '#notifications' do
    it 'is empty without a handler' do
      assert_empty updates(nil).notifications
    end

    it 'is empty when the unstable types are not loaded' do
      out, _err = Open3.capture3('bundle', 'exec', 'ruby', '-I', 'lib', '-e', <<~RUBY)
        require 'acp/sdk'

        updates = ACP::ClientConnection::AuthStatusUpdates.new(handler: ->(_n) {}, logger: nil)
        print updates.notifications.empty?
      RUBY

      assert_equal 'true', out
    end

    it 'drops the notification until the agent advertises auth.status' do
      deliver(updates, status_params)

      assert_empty @log
    end

    it 'logs and drops a malformed notification' do
      deliver(advertised, {})
      error = ACP::Types.parse(ACP::Types::Unstable::AuthStatusUpdateNotification, {})

      assert_equal([[[:warn, "dropped malformed auth/status_update: #{error.message}"]], []], [@logger.drain, @log])
    end

    it 'parses the notification for the handler once the agent advertises auth.status' do
      deliver(advertised, status_params)

      assert_equal [[:auth_status_update, ACP::Types::Unstable::AuthStatusUpdateNotification]], @log
    end
  end
end
