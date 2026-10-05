# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::SessionConfigOption do
  let(:payload) do
    {
      'id' => 'thinking',
      'name' => 'Thinking',
      'description' => 'Extended thinking mode',
      'category' => 'thought_level',
      'type' => 'select',
      'currentValue' => 'high',
      'options' => [
        { 'value' => 'high', 'name' => 'High' },
        { 'group' => 'quality', 'name' => 'Quality', 'options' => [{ 'value' => 'low', 'name' => 'Low' }] }
      ]
    }
  end

  it 'round-trips a select option with grouped items' do
    assert_equal payload, ACP::Types::SessionConfigOption.from_h(payload).to_h
  end

  it 'passes a category outside the open enum through' do
    unknown = payload.merge('category' => 'myapp/verbosity')

    assert_equal 'myapp/verbosity', ACP::Types::SessionConfigOption.from_h(unknown).category
  end

  it 'rejects a malformed item and names its position' do
    invalid = payload.merge('options' => [42])

    error = assert_raises(ACP::Types::ParseError) { ACP::Types::SessionConfigOption.from_h(invalid) }

    assert_equal 'options[0]: expected object, got Integer', error.message
  end
end
