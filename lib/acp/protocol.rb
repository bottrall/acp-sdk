# frozen_string_literal: true

module ACP::Protocol
  PROTOCOL_VERSION = 1 #: Integer

  extend self

  # @rbs capabilities: (ACP::Types::AgentCapabilities | ACP::Types::Unstable::AgentCapabilities | Hash[String, untyped])
  # @rbs return: bool
  def mcp_acp_advertised?(capabilities)
    # The stable McpCapabilities has no acp field, so the gate can only read it
    # when the caller opted in with `require 'acp/types/unstable'`.
    return false unless ACP::Types.unstable_enabled?

    mcp =
      case capabilities
      when ACP::Types::AgentCapabilities, ACP::Types::Unstable::AgentCapabilities
        capabilities.mcp_capabilities #: ACP::Types::McpCapabilities | ACP::Types::Unstable::McpCapabilities?
      else
        # The client's stable parse of the initialize reply drops acp, so the
        # raw capabilities hash is re-parsed with the unstable types.
        ACP::Types::Unstable::AgentCapabilities.from_h(capabilities).mcp_capabilities
      end
    return false unless mcp.is_a?(ACP::Types::Unstable::McpCapabilities)

    mcp.acp ? true : false
  rescue ACP::Types::ParseError, KeyError, TypeError, NoMethodError
    false
  end
end
