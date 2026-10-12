# frozen_string_literal: true

require 'test_helper'

describe ACP::Extensions do
  describe '.validate_name' do
    it 'allows a name starting with an underscore' do
      assert_nil ACP::Extensions.validate_name('_vendor/method')
    end

    it 'rejects a name without the underscore prefix' do
      error = assert_raises(ArgumentError) { ACP::Extensions.validate_name('session/prompt') }

      assert_equal %(extension method names must start with '_' (got "session/prompt")), error.message
    end
  end
end
