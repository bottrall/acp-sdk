# frozen_string_literal: true

module ACP::Protocol
  PROTOCOL_VERSION = 1 #: Integer

  extend self

  # Readers missing along the chain count as unadvertised, so the stable
  # capabilities answer false for the unstable-only paths.
  #
  # @rbs capabilities: untyped
  # @rbs path: Array[Symbol]
  # @rbs return: bool
  def advertised?(capabilities, path)
    # reduce's U pins to the argument's type, but the chain walks through
    # unrelated capability types.
    value = path.reduce(capabilities) { |node, name| node.respond_to?(name) ? node.public_send(name) : nil } #: untyped
    value ? true : false
  end

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
        ACP::Types.parse(ACP::Types::Unstable::McpCapabilities, capabilities['mcpCapabilities'])
      end
    return false unless mcp.is_a?(ACP::Types::Unstable::McpCapabilities)

    mcp.acp ? true : false
  end

  # @rbs capabilities: Hash[String, untyped]
  # @rbs return: bool
  def auth_status_advertised?(capabilities)
    return false unless ACP::Types.unstable_enabled?

    # The client's stable parse of the initialize reply drops auth.status, so
    # the auth sub-object is re-parsed with the unstable type.
    advertised?(ACP::Types.parse(ACP::Types::Unstable::AgentAuthCapabilities, capabilities['auth']), %i[status])
  end

  # @rbs capabilities: Hash[String, untyped]
  # @rbs return: ACP::Types::Unstable::ClientCapabilities?
  def unstable_client_capabilities(capabilities)
    return unless ACP::Types.unstable_enabled?

    # The agent's stable parse of the initialize request drops session.cursors
    # and session.promptSuggestions, so session is re-parsed with the unstable
    # type. Only that sub-object: an unstable-only field elsewhere arrives
    # unvalidated, and a malformed one would fail the whole parse.
    parsed = ACP::Types.parse(ACP::Types::Unstable::ClientCapabilities, capabilities.slice('session'))
    parsed unless parsed.is_a?(ACP::Types::ParseError)
  end
end
