# frozen_string_literal: true

require 'test_helper'

describe ACP::Transport::StderrLogger do
  describe '#warn' do
    it 'writes the message to stderr behind the WARN prefix' do
      _out, err = capture_io { ACP::Transport::StderrLogger.new.warn('slow peer') }

      assert_equal 'acp: WARN: slow peer', err.chomp
    end
  end

  describe '#error' do
    it 'writes the message to stderr behind the ERROR prefix' do
      _out, err = capture_io { ACP::Transport::StderrLogger.new.error('broken pipe') }

      assert_equal 'acp: ERROR: broken pipe', err.chomp
    end
  end
end
