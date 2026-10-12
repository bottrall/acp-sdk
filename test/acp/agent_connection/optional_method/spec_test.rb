# frozen_string_literal: true

require 'test_helper'
require 'acp/types/unstable'

describe ACP::AgentConnection::OptionalMethod::Spec do
  specs = (ACP::AgentConnection::OptionalMethod::SPECS + ACP::AgentConnection::OptionalMethod::UNSTABLE_SPECS).freeze

  auth_method = ACP::Types::AuthMethodAgent.new(id: 'token', name: 'Token').freeze

  providers = lambda {
    ACP::Types::InitializeResponse.new(
      protocol_version: 1,
      agent_capabilities: ACP::Types::Unstable::AgentCapabilities.new(providers: ACP::Types::Unstable::ProvidersCapabilities.new)
    )
  }

  advertised = {
    authenticate: lambda {
      ACP::Types::InitializeResponse.new(protocol_version: 1, auth_methods: [auth_method])
    },
    load_session: lambda {
      ACP::Types::InitializeResponse.new(
        protocol_version: 1, agent_capabilities: ACP::Types::AgentCapabilities.new(load_session: true)
      )
    },
    list_sessions: lambda {
      ACP::Types::InitializeResponse.new(
        protocol_version: 1,
        agent_capabilities: ACP::Types::AgentCapabilities.new(
          session_capabilities: ACP::Types::SessionCapabilities.new(list: ACP::Types::SessionListCapabilities.new)
        )
      )
    },
    resume_session: lambda {
      ACP::Types::InitializeResponse.new(
        protocol_version: 1,
        agent_capabilities: ACP::Types::AgentCapabilities.new(
          session_capabilities: ACP::Types::SessionCapabilities.new(resume: ACP::Types::SessionResumeCapabilities.new)
        )
      )
    },
    close_session: lambda {
      ACP::Types::InitializeResponse.new(
        protocol_version: 1,
        agent_capabilities: ACP::Types::AgentCapabilities.new(
          session_capabilities: ACP::Types::SessionCapabilities.new(close: ACP::Types::SessionCloseCapabilities.new)
        )
      )
    },
    delete_session: lambda {
      ACP::Types::InitializeResponse.new(
        protocol_version: 1,
        agent_capabilities: ACP::Types::AgentCapabilities.new(
          session_capabilities: ACP::Types::SessionCapabilities.new(delete: ACP::Types::SessionDeleteCapabilities.new)
        )
      )
    },
    logout: lambda {
      ACP::Types::InitializeResponse.new(
        protocol_version: 1,
        agent_capabilities: ACP::Types::AgentCapabilities.new(
          auth: ACP::Types::AgentAuthCapabilities.new(logout: ACP::Types::LogoutCapabilities.new)
        )
      )
    },
    fork_session: lambda {
      ACP::Types::InitializeResponse.new(
        protocol_version: 1,
        agent_capabilities: ACP::Types::Unstable::AgentCapabilities.new(
          session_capabilities: ACP::Types::Unstable::SessionCapabilities.new(fork: ACP::Types::Unstable::SessionForkCapabilities.new)
        )
      )
    },
    list_providers: providers,
    set_provider: providers,
    disable_provider: providers
  }.freeze

  it 'parametrises every optional method in the data table' do
    assert_equal advertised.keys.sort, specs.map(&:agent_method).sort
  end

  it 'is frozen, including its path' do
    spec = specs.first

    assert_predicate spec, :frozen?
    assert_predicate spec.path, :frozen?
  end

  it 'advertises nothing when the initialize response has no capabilities' do
    response = ACP::Types::InitializeResponse.new(protocol_version: 1, agent_capabilities: ACP::Types::AgentCapabilities.new)

    refute(specs.any? { |spec| spec.advertised?(response) })
  end

  specs.each do |spec|
    response = advertised.fetch(spec.agent_method)

    it "advertises #{spec.rpc_method} when its capability is set" do
      assert spec.advertised?(response.call)
    end

    it "does not advertise #{spec.rpc_method} when its capability is unset" do
      refute spec.advertised?(ACP::Types::InitializeResponse.new(protocol_version: 1))
    end
  end
end
