# frozen_string_literal: true

require 'test_helper'

class CheckFakeType
  def initialize(&parse)
    @parse = parse
  end

  def from_h(value)
    @parse.call(value)
  end

  def from_a(value)
    @parse.call(value)
  end
end

describe ACP::Types::Check do
  describe '.key' do
    it 'returns the value under a present key, even when it is nil' do
      assert_equal 's1', ACP::Types::Check.key({ 'sessionId' => 's1' }, 'sessionId')
      assert_nil ACP::Types::Check.key({ 'sessionId' => nil }, 'sessionId')
    end

    it 'rejects a missing key as required' do
      assert_rejected(['sessionId'], 'is required') { ACP::Types::Check.key({}, 'sessionId') }
    end
  end

  describe '.string' do
    it 'returns a String' do
      assert_equal 'ok', ACP::Types::Check.string('ok', 'title')
    end

    it 'passes nil and the unset sentinel through when allowed' do
      assert_nil ACP::Types::Check.string(nil, 'title', allow_nil: true)
      assert_equal :unset, ACP::Types::Check.string(:unset, 'title', allow_unset: true)
    end

    it 'rejects nil when only the unset sentinel is allowed' do
      assert_rejected(['title'], 'expected String, got null') do
        ACP::Types::Check.string(nil, 'title', allow_unset: true)
      end
    end

    it 'rejects the unset sentinel when only nil is allowed' do
      assert_rejected(['title'], 'expected String, got Symbol') do
        ACP::Types::Check.string(:unset, 'title', allow_nil: true)
      end
    end

    it 'rejects any other value, naming its class' do
      assert_rejected(['title'], 'expected String, got Integer') { ACP::Types::Check.string(42, 'title') }
    end

    it 'names booleans by their JSON literal' do
      assert_rejected(['title'], 'expected String, got true') { ACP::Types::Check.string(true, 'title') }
      assert_rejected(['title'], 'expected String, got false') { ACP::Types::Check.string(false, 'title') }
    end

    it 'reports an Array path as the segments given' do
      assert_rejected(['prompt', 0, 'text'], 'expected String, got Integer') do
        ACP::Types::Check.string(42, ['prompt', 0, 'text'])
      end
    end
  end

  describe '.boolean' do
    it 'returns true and false' do
      assert_equal [true, false], [ACP::Types::Check.boolean(true, 'done'), ACP::Types::Check.boolean(false, 'done')]
    end

    it 'passes nil and the unset sentinel through when allowed' do
      assert_nil ACP::Types::Check.boolean(nil, 'done', allow_nil: true)
      assert_equal :unset, ACP::Types::Check.boolean(:unset, 'done', allow_unset: true)
    end

    it 'rejects any other value' do
      assert_rejected(['done'], 'expected boolean, got Integer') { ACP::Types::Check.boolean(1, 'done') }
    end
  end

  describe '.integer' do
    it 'returns an unbounded Integer' do
      assert_equal(-7, ACP::Types::Check.integer(-7, 'line'))
    end

    it 'returns an Integer on either inclusive bound' do
      assert_equal 0, ACP::Types::Check.integer(0, 'line', min: 0, max: 9)
      assert_equal 9, ACP::Types::Check.integer(9, 'line', min: 0, max: 9)
    end

    it 'passes nil and the unset sentinel through when allowed' do
      assert_nil ACP::Types::Check.integer(nil, 'line', min: 0, allow_nil: true)
      assert_equal :unset, ACP::Types::Check.integer(:unset, 'line', min: 0, allow_unset: true)
    end

    it 'rejects a non-Integer' do
      assert_rejected(['line'], 'expected Integer, got Float') { ACP::Types::Check.integer(1.5, 'line') }
    end

    it 'rejects an Integer below the minimum, naming the bound' do
      assert_rejected(['line'], 'expected Integer >= 0, got Integer') do
        ACP::Types::Check.integer(-1, 'line', min: 0)
      end
    end

    it 'rejects an Integer above the maximum, naming the bound' do
      assert_rejected(['line'], 'expected Integer <= 9, got Integer') do
        ACP::Types::Check.integer(10, 'line', max: 9)
      end
    end

    it 'names both bounds when both are set' do
      assert_rejected(['line'], 'expected Integer between 0 and 9, got Integer') do
        ACP::Types::Check.integer(10, 'line', min: 0, max: 9)
      end
    end
  end

  describe '.number' do
    it 'returns an unbounded Float or Integer' do
      assert_equal [0.5, 3], [ACP::Types::Check.number(0.5, 'priority'), ACP::Types::Check.number(3, 'priority')]
    end

    it 'returns a number on either inclusive bound' do
      assert_equal 0, ACP::Types::Check.number(0, 'priority', min: 0, max: 1)
      assert_equal 1, ACP::Types::Check.number(1, 'priority', min: 0, max: 1)
    end

    it 'passes nil and the unset sentinel through when allowed' do
      assert_nil ACP::Types::Check.number(nil, 'priority', min: 0, allow_nil: true)
      assert_equal :unset, ACP::Types::Check.number(:unset, 'priority', min: 0, allow_unset: true)
    end

    it 'rejects a non-Numeric' do
      assert_rejected(['priority'], 'expected Numeric, got String') { ACP::Types::Check.number('1', 'priority') }
    end

    it 'rejects a number below the minimum, naming the bound' do
      assert_rejected(['priority'], 'expected Numeric >= 0, got Float') do
        ACP::Types::Check.number(-0.5, 'priority', min: 0)
      end
    end

    it 'rejects a number above the maximum, naming the bound' do
      assert_rejected(['priority'], 'expected Numeric <= 1, got Float') do
        ACP::Types::Check.number(1.5, 'priority', max: 1)
      end
    end

    it 'names both bounds when both are set' do
      assert_rejected(['priority'], 'expected Numeric between 0 and 1, got Integer') do
        ACP::Types::Check.number(2, 'priority', min: 0, max: 1)
      end
    end
  end

  describe '.enum' do
    it 'returns a listed value' do
      assert_equal 'end_turn', ACP::Types::Check.enum('end_turn', 'stopReason', %w[end_turn cancelled])
    end

    it 'passes nil and the unset sentinel through when allowed' do
      assert_nil ACP::Types::Check.enum(nil, 'stopReason', %w[end_turn], allow_nil: true)
      assert_equal :unset, ACP::Types::Check.enum(:unset, 'stopReason', %w[end_turn], allow_unset: true)
    end

    it 'rejects an unlisted value, naming the alternatives' do
      assert_rejected(['stopReason'], 'expected one of "end_turn", "cancelled", got Integer') do
        ACP::Types::Check.enum(42, 'stopReason', %w[end_turn cancelled])
      end
    end
  end

  describe '.one_of' do
    it 'passes nil and the unset sentinel through when allowed, without checking items' do
      assert_nil ACP::Types::Check.one_of(nil, 'id', [Array], allow_nil: true) { flunk }
      assert_equal :unset, ACP::Types::Check.one_of(:unset, 'id', [Array], allow_unset: true) { flunk }
    end

    it 'rejects a value of none of the classes, naming them' do
      assert_rejected(['id'], 'expected Integer | String, got Array') do
        ACP::Types::Check.one_of([], 'id', [Integer, String])
      end
    end

    it 'returns a non-Array value without checking items' do
      assert_equal 42, ACP::Types::Check.one_of(42, 'id', [Integer, Array]) { flunk }
    end

    it 'returns an Array as it is when no item check is given' do
      assert_equal ['a', 2], ACP::Types::Check.one_of(['a', 2], 'content', [String, Array])
    end

    it 'yields each Array item with its indexed path and returns the Array itself' do
      value = %w[a b]
      yielded = []
      result = ACP::Types::Check.one_of(value, 'content', [String, Array]) do |item, path|
        yielded << [item, path]
        :ignored
      end

      assert_equal [[['a', ['content', 0]], ['b', ['content', 1]]], value], [yielded, result]
    end

    it 'extends an Array path with each item index' do
      yielded = []
      ACP::Types::Check.one_of(%w[a b], ['prompt', 0], [Array]) { |_item, path| yielded << path }

      assert_equal [['prompt', 0, 0], ['prompt', 0, 1]], yielded
    end
  end

  describe '.hash' do
    it 'passes nil and the unset sentinel through when allowed, without checking values' do
      assert_nil ACP::Types::Check.hash(nil, 'env', allow_nil: true) { flunk }
      assert_equal :unset, ACP::Types::Check.hash(:unset, 'env', allow_unset: true) { flunk }
    end

    it 'rejects a non-Hash' do
      assert_rejected(['env'], 'expected object, got Array') { ACP::Types::Check.hash([], 'env') { flunk } }
    end

    it 'maps each value through the check, yielding its keyed path' do
      parsed = ACP::Types::Check.hash({ 'A' => 1, 'B' => 2 }, 'env') { |item, path| [item, path] }

      assert_equal({ 'A' => [1, %w[env A]], 'B' => [2, %w[env B]] }, parsed)
    end

    it 'extends an Array path with each key' do
      parsed = ACP::Types::Check.hash({ 'A' => 1, 'B' => 2 }, ['servers', 1]) { |_item, path| path }

      assert_equal({ 'A' => ['servers', 1, 'A'], 'B' => ['servers', 1, 'B'] }, parsed)
    end
  end

  describe '.array' do
    it 'passes nil and the unset sentinel through when allowed, without checking items' do
      assert_nil ACP::Types::Check.array(nil, 'roles', allow_nil: true) { flunk }
      assert_equal :unset, ACP::Types::Check.array(:unset, 'roles', allow_unset: true) { flunk }
    end

    it 'rejects a non-Array' do
      assert_rejected(['roles'], 'expected array, got Hash') { ACP::Types::Check.array({}, 'roles') { flunk } }
    end

    it 'maps each item through the check, yielding its indexed path' do
      parsed = ACP::Types::Check.array(%w[a b], 'roles') { |item, path| [item, path] }

      assert_equal [['a', ['roles', 0]], ['b', ['roles', 1]]], parsed
    end

    it 'extends an Array path with each item index' do
      parsed = ACP::Types::Check.array(%w[a b], ['servers', 1]) { |_item, path| path }

      assert_equal [['servers', 1, 0], ['servers', 1, 1]], parsed
    end
  end

  describe '.object' do
    it 'passes nil and the unset sentinel through when allowed, without parsing' do
      type = CheckFakeType.new { flunk }

      assert_nil ACP::Types::Check.object(nil, 'annotations', type, allow_nil: true)
      assert_equal :unset, ACP::Types::Check.object(:unset, 'annotations', type, allow_unset: true)
    end

    it 'rejects a non-Hash without parsing' do
      type = CheckFakeType.new { flunk }

      assert_rejected(['annotations'], 'expected object, got Array') do
        ACP::Types::Check.object([], 'annotations', type)
      end
    end

    it "returns the class's from_h of the Hash" do
      type = CheckFakeType.new { |value| [:parsed, value] }

      assert_equal [:parsed, { 'priority' => 1 }], ACP::Types::Check.object({ 'priority' => 1 }, 'annotations', type)
    end

    it "prefixes a nested ParseError's path with its own" do
      type = CheckFakeType.new { raise ACP::Types::ParseError.new(['audience', 0], 'is wrong') }

      assert_rejected(['annotations', 'audience', 0], 'is wrong') do
        ACP::Types::Check.object({}, 'annotations', type)
      end
    end

    it "prefixes a nested ParseError's path with every segment of an Array path" do
      type = CheckFakeType.new { raise ACP::Types::ParseError.new(['audience', 0], 'is wrong') }

      assert_rejected(['servers', 1, 'audience', 0], 'is wrong') do
        ACP::Types::Check.object({}, ['servers', 1], type)
      end
    end
  end

  describe '.objects' do
    it 'passes nil and the unset sentinel through when allowed, without parsing' do
      type = CheckFakeType.new { flunk }

      assert_nil ACP::Types::Check.objects(nil, 'options', type, allow_nil: true)
      assert_equal :unset, ACP::Types::Check.objects(:unset, 'options', type, allow_unset: true)
    end

    it 'rejects a non-Array without parsing' do
      type = CheckFakeType.new { flunk }

      assert_rejected(['options'], 'expected array, got Hash') { ACP::Types::Check.objects({}, 'options', type) }
    end

    it 'rejects a non-Hash item at its index without parsing' do
      type = CheckFakeType.new { flunk }

      assert_rejected(['options', 1], 'expected object, got Integer') do
        ACP::Types::Check.objects([{}, 2], 'options', type)
      end
    end

    it 'rejects a non-Hash item at its index under an Array path' do
      type = CheckFakeType.new { flunk }

      assert_rejected(['servers', 1, 1], 'expected object, got Integer') do
        ACP::Types::Check.objects([{}, 2], ['servers', 1], type)
      end
    end

    it "returns the class's from_a of the Array" do
      type = CheckFakeType.new { |value| [:parsed, value] }

      assert_equal [:parsed, [{ 'id' => 'a' }]], ACP::Types::Check.objects([{ 'id' => 'a' }], 'options', type)
    end

    it "prefixes a nested ParseError's path with its own" do
      type = CheckFakeType.new { raise ACP::Types::ParseError.new([0, 'name'], 'is wrong') }

      assert_rejected(['options', 0, 'name'], 'is wrong') { ACP::Types::Check.objects([{}], 'options', type) }
    end

    it "prefixes a nested ParseError's path with every segment of an Array path" do
      type = CheckFakeType.new { raise ACP::Types::ParseError.new([0, 'name'], 'is wrong') }

      assert_rejected(['servers', 1, 0, 'name'], 'is wrong') do
        ACP::Types::Check.objects([{}], ['servers', 1], type)
      end
    end
  end

  private

  def assert_rejected(segments, detail, &)
    error = assert_raises(ACP::Types::ParseError, &)

    assert_equal segments, error.segments
    assert_equal ACP::Types::ParseError.new(segments, detail).message, error.message
  end
end
