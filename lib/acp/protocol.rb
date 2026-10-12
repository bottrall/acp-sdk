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
      when Hash
        # The client's stable parse of the initialize reply drops acp, so
        # mcpCapabilities is re-parsed from the raw hash with the unstable
        # type. Only that sub-object: the other unstable fields arrive
        # unvalidated and must not decide whether MCP is advertised.
        raw = capabilities['mcpCapabilities']
        ACP::Types::Unstable::McpCapabilities.from_h(raw) if raw.is_a?(Hash)
      end
    return false unless mcp.is_a?(ACP::Types::Unstable::McpCapabilities)

    mcp.acp ? true : false
  rescue ACP::Types::ParseError
    false
  end
end
