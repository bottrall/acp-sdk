# frozen_string_literal: true

module ACP::Types
  # Lives on ACP::Types rather than ACP::Types::Unstable because the callers
  # run in the stable-only load, where even naming the inner module would raise
  # NameError.
  #
  # @rbs return: bool
  def self.unstable_enabled?
    !defined?(ACP::Types::Unstable).nil?
  end

  # Generated from_h checks only nested values, so a payload that is not an
  # object is rejected here: a String would answer nil for every key and parse
  # as an empty object.
  #
  # @rbs type: ACP::Transport::_Parser
  # @rbs payload: untyped
  # @rbs return: untyped
  def self.parse(type, payload)
    ACP::Types::Check.object(payload, [], type)
  rescue ACP::Types::ParseError => e
    e
  end
end
