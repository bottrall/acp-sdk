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

  describe '.validate_names' do
    it 'allows names that all start with an underscore' do
      assert_equal %w[_a _b], ACP::Extensions.validate_names(%w[_a _b])
    end

    it 'rejects the first name without the underscore prefix' do
      error = assert_raises(ArgumentError) { ACP::Extensions.validate_names(%w[_a b c]) }

      assert_equal %(extension method names must start with '_' (got "b")), error.message
    end
  end
end
