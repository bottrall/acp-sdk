# frozen_string_literal: true

require 'test_helper'
require 'acp/types/unstable'

describe ACP::AgentConnection::OptionalMethod do
  specs = (ACP::AgentConnection::OptionalMethod::SPECS + ACP::AgentConnection::OptionalMethod::UNSTABLE_SPECS).freeze

  it 'freezes both spec tables' do
    assert_predicate ACP::AgentConnection::OptionalMethod::SPECS, :frozen?
    assert_predicate ACP::AgentConnection::OptionalMethod::UNSTABLE_SPECS, :frozen?
  end

  it 'routes each optional method to a unique agent method' do
    agent_methods = specs.map(&:agent_method)

    assert_equal agent_methods.size, agent_methods.uniq.size
  end

  it 'keeps the unstable-only specs out of the stable table' do
    assert_equal %i[fork_session list_providers set_provider disable_provider].sort,
                 ACP::AgentConnection::OptionalMethod::UNSTABLE_SPECS.map(&:agent_method).sort
  end
end
