# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::AvailableCommandsUpdate do
  let(:payload) do
    {
      'availableCommands' => [
        {
          'name' => 'web',
          'description' => 'Search the web for information',
          'input' => { 'hint' => 'query to search for' }
        },
        { 'name' => 'test', 'description' => 'Run tests for the current project' }
      ]
    }
  end

  it 'round-trips the slash commands example from the protocol docs' do
    assert_equal payload, ACP::Types::AvailableCommandsUpdate.from_h(payload).to_h
  end

  it 'builds unstructured command input' do
    command = ACP::Types::AvailableCommandsUpdate.from_h(payload).available_commands.first

    assert_instance_of ACP::Types::UnstructuredCommandInput, command&.input
  end
end
