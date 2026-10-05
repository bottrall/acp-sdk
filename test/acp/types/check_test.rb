# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::ParseError do
  it 'names the failing path and the reason' do
    error = ACP::Types::ParseError.new(['sessionId'], 'expected String, got Integer')

    assert_equal ['sessionId: expected String, got Integer', 'sessionId'], [error.message, error.path]
  end

  it 'renders array indexes in brackets and nested keys behind dots' do
    error = ACP::Types::ParseError.new(['prompt', 0, 'text'], 'expected String, got Integer')

    assert_equal 'prompt[0].text: expected String, got Integer', error.message
  end

  it 'prepends container segments without losing the original path' do
    error = ACP::Types::ParseError.new(['audience', 1], 'expected String, got Integer').prefix('annotations')

    assert_equal 'annotations.audience[1]: expected String, got Integer', error.message
  end
end

describe ACP::Types::Check do
  it 'answers a missing key with the key path' do
    error = assert_raises(ACP::Types::ParseError) { ACP::Types::Check.key({}, 'sessionId') }

    assert_equal 'sessionId: is required', error.message
    assert_equal 's1', ACP::Types::Check.key({ 'sessionId' => 's1' }, 'sessionId')
  end

  it 'checks strings, allowing nil and the unset sentinel only when asked' do
    assert_equal 'ok', ACP::Types::Check.string('ok', 'title')
    assert_nil ACP::Types::Check.string(nil, 'title', allow_nil: true)
    assert_equal :unset, ACP::Types::Check.string(:unset, 'title', allow_unset: true)

    error = assert_raises(ACP::Types::ParseError) { ACP::Types::Check.string(42, 'title') }

    assert_equal 'title: expected String, got Integer', error.message
    message = parse_error { ACP::Types::Check.string(nil, 'title') }

    assert_equal 'title: expected String, got null', message
  end

  it 'checks booleans' do
    assert ACP::Types::Check.boolean(true, 'done')
    refute ACP::Types::Check.boolean(false, 'done')

    error = assert_raises(ACP::Types::ParseError) { ACP::Types::Check.boolean(1, 'done') }

    assert_equal 'done: expected boolean, got Integer', error.message
  end

  it 'checks integer and number ranges' do
    assert_equal 0, ACP::Types::Check.integer(0, 'line', min: 0, max: 65_535)
    assert_equal 65_535, ACP::Types::Check.integer(65_535, 'line', min: 0, max: 65_535)
    assert_in_delta 0.5, ACP::Types::Check.number(0.5, 'priority')

    error = assert_raises(ACP::Types::ParseError) { ACP::Types::Check.integer(-1, 'line', min: 0, max: 65_535) }

    assert_equal 'line: expected Integer between 0 and 65535, got Integer', error.message
    assert_equal(
      'line: expected Integer >= 0, got Float',
      parse_error do
        ACP::Types::Check.integer(1.5, 'line', min: 0)
      end
    )
    assert_equal(
      'priority: expected Numeric >= 0, got Integer',
      parse_error { ACP::Types::Check.number(-1, 'priority', min: 0) }
    )
  end

  it 'rejects values outside a closed enum and names the alternatives' do
    values = %w[end_turn cancelled]

    error = assert_raises(ACP::Types::ParseError) { ACP::Types::Check.enum(42, 'stopReason', values) }

    assert_equal 'stopReason: expected one of "end_turn", "cancelled", got Integer', error.message
    assert_equal 'end_turn', ACP::Types::Check.enum('end_turn', 'stopReason', values)
  end

  it 'rejects values outside a primitive union' do
    error = assert_raises(ACP::Types::ParseError) { ACP::Types::Check.one_of([], 'id', [Integer, String]) }

    assert_equal 'id: expected Integer | String, got Array', error.message
    assert_equal 42, ACP::Types::Check.one_of(42, 'id', [Integer, String], allow_nil: true)
  end

  it 'checks array items and reports their index' do
    roles = %w[a b]
    parsed = ACP::Types::Check.array(roles, 'roles') { |item, path| ACP::Types::Check.string(item, path) }

    assert_equal roles, parsed
    message = parse_error do
      ACP::Types::Check.array(['a', 2], 'roles') { |item, path| ACP::Types::Check.string(item, path) }
    end

    assert_equal 'roles[1]: expected String, got Integer', message
  end

  it 'checks hash values and reports their key' do
    env = { 'K' => 'v' }
    parsed = ACP::Types::Check.hash(env, 'env') { |value, path| ACP::Types::Check.string(value, path) }

    assert_equal env, parsed
    message = parse_error do
      ACP::Types::Check.hash({ 'K' => 1 }, 'env') { |value, path| ACP::Types::Check.string(value, path) }
    end

    assert_equal 'env.K: expected String, got Integer', message
  end

  it 'wraps nested from_h failures with the field path' do
    parsed = ACP::Types::Check.object({ 'audience' => ['user'] }, 'annotations', ACP::Types::Annotations)

    assert_instance_of ACP::Types::Annotations, parsed
    message = parse_error do
      ACP::Types::Check.object({ 'audience' => [42] }, 'annotations', ACP::Types::Annotations)
    end

    assert_equal 'annotations.audience[0]: expected one of "assistant", "user", got Integer', message
  end

  it 'checks every item of an array union is an object before from_a' do
    message = parse_error do
      ACP::Types::Check.objects([{}, 2], 'options', ACP::Types::SessionConfigSelectOptions)
    end

    assert_equal 'options[1]: expected object, got Integer', message
  end

  private

  def parse_error(&)
    assert_raises(ACP::Types::ParseError, &).message
  end
end
