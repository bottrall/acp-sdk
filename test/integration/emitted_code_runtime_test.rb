# frozen_string_literal: true

require 'test_helper'
require_relative '../codegen/type_generator/fixtures'

describe 'emitted code at runtime' do
  it 'reports a failure inside a nested guard at its absolute path' do
    Object.module_eval(FixtureSchemas::FILES.fetch('step.rb'))
    Object.module_eval(FixtureSchemas::FILES.fetch('widget_request.rb'))

    error = assert_raises(ACP::Types::ParseError) do
      ACP::Types::WidgetRequest.from_h({ 'label' => 'w', 'steps' => [{ 'index' => 'nope' }] })
    end

    assert_equal ['steps', 0, 'index'], error.segments
  end
end
