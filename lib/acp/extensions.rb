# frozen_string_literal: true

# Shared by the connections' handler maps and send paths, so a plain method
# name cannot slip into the extension routes.
module ACP::Extensions
  # @rbs name: String
  # @rbs return: void
  def self.validate_name(name)
    return if name.start_with?('_')

    raise ArgumentError, "extension method names must start with '_' (got #{name.inspect})"
  end
end
