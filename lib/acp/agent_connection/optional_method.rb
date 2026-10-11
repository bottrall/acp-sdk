# frozen_string_literal: true

module ACP::AgentConnection::OptionalMethod
  # The stable optional methods and their advertisement data: how the request
  # is routed and where on the InitializeResponse the capability lives.
  SPECS = [
    Spec.new(rpc_method: 'authenticate', agent_method: :authenticate, path: %i[auth_methods any?]),
    Spec.new(rpc_method: 'session/load', agent_method: :load_session, path: %i[agent_capabilities load_session]),
    Spec.new(
      rpc_method: 'session/list',
      agent_method: :list_sessions,
      path: %i[agent_capabilities session_capabilities list]
    ),
    Spec.new(
      rpc_method: 'session/resume',
      agent_method: :resume_session,
      path: %i[agent_capabilities session_capabilities resume]
    ),
    Spec.new(
      rpc_method: 'session/close',
      agent_method: :close_session,
      path: %i[agent_capabilities session_capabilities close]
    ),
    Spec.new(
      rpc_method: 'session/delete',
      agent_method: :delete_session,
      path: %i[agent_capabilities session_capabilities delete]
    ),
    Spec.new(rpc_method: 'logout', agent_method: :logout, path: %i[agent_capabilities auth logout])
  ].freeze #: Array[Spec]

  UNSTABLE_SPECS = [
    Spec.new(
      rpc_method: 'session/fork',
      agent_method: :fork_session,
      path: %i[agent_capabilities session_capabilities fork]
    ),
    Spec.new(rpc_method: 'providers/list', agent_method: :list_providers, path: %i[agent_capabilities providers]),
    Spec.new(rpc_method: 'providers/set', agent_method: :set_provider, path: %i[agent_capabilities providers]),
    Spec.new(rpc_method: 'providers/disable', agent_method: :disable_provider, path: %i[agent_capabilities providers])
  ].freeze #: Array[Spec]
end
