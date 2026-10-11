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
end
