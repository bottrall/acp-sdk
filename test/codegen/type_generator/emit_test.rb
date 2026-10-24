# frozen_string_literal: true

require 'test_helper'
require_relative '../../../codegen/type_generator'

describe TypeGenerator::Emit do
  emit = TypeGenerator::Emit
  check = TypeGenerator::CHECK
  raw_hash = TypeGenerator::RAW_HASH

  def type_of(rbs = 'String', **)
    TypeGenerator::Type.new(rbs:, **)
  end

  def field(attr, type: type_of, required: true, nullable: false, json: attr, **)
    TypeGenerator::Field.new(attr:, type:, required:, nullable:, json:, **)
  end

  def filling(column, around)
    'x' * (TypeGenerator::MAX_LINE_LENGTH - column - around.length)
  end

  describe '.class_file' do
    it 'files the class at its Plan path, under the schema header, with a section per accessor and method' do
      defs = TypeGenerator::Schema.new({}, header: "# header\n")

      file = emit.class_file(defs, 'ACP::Types::Note', [field('text')])

      assert_equal [TypeGenerator::Naming.path('ACP::Types::Note'), <<~RUBY], file
        # header

        class ACP::Types::Note
          # @dynamic text
          attr_reader :text #: String

          # @rbs text: String
          # @rbs return: void
          def initialize(text:)
            @text = text
            freeze
          end

          # @rbs hash: #{raw_hash}
          # @rbs return: ACP::Types::Note
          def self.from_h(hash)
            new(text: #{check}.key(hash, 'text'))
          end

          # @rbs return: #{raw_hash}
          def to_h
            { 'text' => text }
          end
        end
      RUBY
    end

    it 'hands the tag to to_h and emits no accessor section for a fieldless class' do
      defs = TypeGenerator::Schema.new({}, header: "# header\n")

      _path, source = emit.class_file(defs, 'ACP::Types::Blend::Tagged', [], tag: %w[type tagged])

      assert_equal <<~RUBY, source
        # header

        class ACP::Types::Blend::Tagged
          # @rbs return: void
          def initialize
            freeze
          end

          # @rbs _hash: #{raw_hash}
          # @rbs return: ACP::Types::Blend::Tagged
          def self.from_h(_hash)
            new
          end

          # @rbs return: #{raw_hash}
          def to_h
            { 'type' => 'tagged' }
          end
        end
      RUBY
    end
  end

  describe '.source' do
    it 'indents each section inside the opening, separated by blank lines, below the header' do
      assert_equal "# header\n\nmodule M\n  a\n  b\n\n  c\nend\n",
                   emit.source('module M', [%w[a b], %w[c]], "# header\n")
    end
  end

  describe '.indent' do
    it 'prefixes every line with the given number of spaces' do
      assert_equal ['    a', '    b'], emit.indent(%w[a b], 4)
    end
  end

  describe '.rbs_type' do
    it 'is the bare type of a field that is never nil' do
      assert_equal 'String', emit.rbs_type(field('id'))
    end

    it 'adds the unset sentinel to a clearable field' do
      assert_equal 'String? | :unset', emit.rbs_type(field('title', required: false, clearable: true))
    end

    it 'is the optional type of a field that is optional or nullable' do
      types = [field('note', required: false), field('meta', nullable: true)].map { |nilable| emit.rbs_type(nilable) }

      assert_equal %w[String? String?], types
    end
  end

  describe '.attr_reader' do
    it 'declares the reader as dynamic and annotates its type inline' do
      assert_equal ['# @dynamic note', 'attr_reader :note #: String?'], emit.attr_reader(field('note', required: false))
    end
  end

  describe '.initialize_method' do
    it 'takes no parameters and only freezes when there are no fields' do
      assert_equal ['# @rbs return: void', 'def initialize', '  freeze', 'end'], emit.initialize_method([])
    end

    it 'puts required keywords first, nullable or not, defaults optional ones to nil and clearable ones to :unset' do
      fields = [
        field('note', required: false),
        field('id'),
        field('title', required: false, clearable: true),
        field('meta', nullable: true)
      ]

      assert_equal(
        [
          '# @rbs note: String?',
          '# @rbs id: String',
          '# @rbs title: String? | :unset',
          '# @rbs meta: String?',
          '# @rbs return: void',
          'def initialize(id:, meta:, note: nil, title: :unset)',
          '  @note = note',
          '  @id = id',
          '  @title = title',
          '  @meta = meta',
          '  freeze',
          'end'
        ],
        emit.initialize_method(fields)
      )
    end

    it 'measures the signature from the class body indent' do
      fitting = filling(2, 'def initialize(:)')

      signatures = [fitting, "#{fitting}x"].map { |attr| emit.initialize_method([field(attr)])[2] }

      assert_equal ["def initialize(#{fitting}:)", 'def initialize('], signatures
    end
  end

  describe '.from_h_method' do
    it 'ignores the hash and calls a bare new when there are no fields' do
      assert_equal(
        [
          "# @rbs _hash: #{raw_hash}",
          '# @rbs return: ACP::Types::Empty',
          'def self.from_h(_hash)',
          '  new',
          'end'
        ],
        emit.from_h_method('ACP::Types::Empty', [])
      )
    end

    it 'passes each blockless expression straight to new' do
      fields = [field('id'), field('note', required: false)]

      assert_equal(
        [
          "# @rbs hash: #{raw_hash}",
          '# @rbs return: ACP::Types::Note',
          'def self.from_h(hash)',
          "  new(id: #{check}.key(hash, 'id'), note: hash['note'])",
          'end'
        ],
        emit.from_h_method('ACP::Types::Note', fields)
      )
    end

    it 'assigns an expression that takes a block to a local and passes it by shorthand' do
      fields = [
        field('tags', type: type_of('Array[String]', check: [:array, [:string]]), required: false),
        field('note', required: false)
      ]

      assert_equal(
        [
          "  tags = #{check}.array(hash['tags'], 'tags', allow_nil: true) do |item, path|",
          "    #{check}.string(item, path)",
          '  end',
          "  new(tags:, note: hash['note'])"
        ],
        emit.from_h_method('ACP::Types::Note', fields)[3..-2]
      )
    end

    it 'measures a local assignment from the method body indent' do
      list = type_of('Array[String]', check: [:array, [:string]])
      one_line = " = #{check}.array(hash['j'], 'j', allow_nil: true) { |item, path| #{check}.string(item, path) }"
      fitting = filling(4, one_line)

      assignments = [fitting, "#{fitting}x"].map do |attr|
        emit.from_h_method('ACP::Types::Note', [field(attr, type: list, required: false, json: 'j')])[3]
      end

      assert_equal(
        ["  #{fitting}#{one_line}", "  #{fitting}x = #{check}.array(hash['j'], 'j', allow_nil: true) do |item, path|"],
        assignments
      )
    end

    it 'measures the new call from the method body indent' do
      fitting = filling(4, "new(: hash['j'])")

      calls = [fitting, "#{fitting}x"].map do |attr|
        emit.from_h_method('ACP::Types::Note', [field(attr, required: false, json: 'j')])[3]
      end

      assert_equal ["  new(#{fitting}: hash['j'])", '  new('], calls
    end
  end

  describe '.new_call' do
    it 'is a bare new without arguments' do
      assert_equal ['new'], emit.new_call([], 4)
    end

    it 'stays on one line when it ends exactly at the line limit' do
      value = filling(4, 'new(a: , b:)')

      assert_equal ["new(a: #{value}, b:)"], emit.new_call([['a', value], ['b', nil]], 4)
    end

    it 'puts one argument per line, comma-separated, once it passes the line limit' do
      value = "#{filling(4, 'new(a:, b: , c:)')}x"

      assert_equal ['new(', '  a:,', "  b: #{value},", '  c:', ')'],
                   emit.new_call([['a', nil], ['b', value], ['c', nil]], 4)
    end

    it 'leaves the comma off a last argument that carries an expression' do
      value = "#{filling(4, 'new(a:, b: )')}x"

      assert_equal ['new(', '  a:,', "  b: #{value}", ')'], emit.new_call([['a', nil], ['b', value]], 4)
    end

    it 'measures a wrapped argument from two columns further in' do
      fitting = filling(6, 'a: f()')

      calls = [fitting, "#{fitting}x"].map { |value| emit.new_call([['a', ['f', [value], nil, nil]]], 4) }

      assert_equal [['new(', "  a: f(#{fitting})", ')'], ['new(', '  a: f(', "    #{fitting}x", '  )', ')']], calls
    end
  end

  describe '.new_arg' do
    it 'is the keyword shorthand when the value lives in a local' do
      assert_equal 'steps:', emit.new_arg('steps', nil)
    end

    it 'inlines the expression after the keyword otherwise' do
      assert_equal "label: f(hash, 'label')", emit.new_arg('label', ['f', ['hash', "'label'"], nil, nil])
    end
  end

  describe '.wrap' do
    it 'is the single line, without building the items, when it fits' do
      assert_equal ['f(a)'], emit.wrap('f(a)', 4, 'f(', ')') { flunk 'built the items' }
    end

    it 'indents every line of every item between the opening and closing once the single line does not fit' do
      single = "#{filling(4, '')}x"

      assert_equal ['f(', '  a,', '  g(', '    b', '  )', ')'],
                   emit.wrap(single, 4, 'f(', ')') { [['a,'], ['g(', '  b', ')']] }
    end
  end

  describe '.fits?' do
    it 'is true for a line that ends exactly at the line limit' do
      assert emit.fits?(filling(4, ''), 4)
    end

    it 'is false for a line that passes the line limit' do
      refute emit.fits?("#{filling(4, '')}x", 4)
    end
  end

  describe '.commas' do
    it 'pairs every item but the last with a comma' do
      assert_equal [['a', ','], ['b', ','], ['c', '']], emit.commas(%w[a b c])
    end
  end

  describe '.from_expression' do
    it 'converts the whole hash for a flattened field, never nil-safely' do
      flattened = field(
        'mode',
        type: type_of('ACP::Types::Mode::t', from: [:call, 'ACP::Types::Mode.from_h']),
        required: false,
        json: nil,
        flattened: true
      )

      assert_equal 'ACP::Types::Mode.from_h(hash)', emit.from_expression(flattened)
    end

    it 'reads a required unchecked field through the key guard' do
      assert_equal "#{check}.key(hash, 'sessionId')", emit.from_expression(field('session_id', json: 'sessionId'))
    end

    it 'reads a required nullable unchecked field through the key guard all the same' do
      assert_equal "#{check}.key(hash, 'meta')", emit.from_expression(field('meta', nullable: true))
    end

    it 'reads a clearable unchecked field at its JSON key, with the unset sentinel as its default' do
      clearable = field('updated_at', required: false, clearable: true, json: 'updatedAt')

      assert_equal "hash.fetch('updatedAt', :unset)", emit.from_expression(clearable)
    end

    it 'reads an optional unchecked field with a plain lookup' do
      assert_equal "hash['noteText']", emit.from_expression(field('note_text', required: false, json: 'noteText'))
    end

    it 'converts a required unchecked field around the inlined key guard' do
      converted = field('id', type: type_of('ACP::Types::Id', from: [:call, 'ACP::Types::Id.from_h']))

      assert_equal "ACP::Types::Id.from_h(#{check}.key(hash, 'id'))", emit.from_expression(converted)
    end

    it 'converts a required nullable unchecked field nil-safely around the inlined key guard' do
      converted = field('id', type: type_of('ACP::Types::Id', from: [:call, 'ACP::Types::Id.from_h']), nullable: true)

      assert_equal(
        "#{check}.key(hash, 'id')&.then { |value| ACP::Types::Id.from_h(value) }",
        emit.from_expression(converted)
      )
    end

    it 'converts an optional unchecked field nil-safely' do
      converted = field('id', type: type_of('ACP::Types::Id', from: [:call, 'ACP::Types::Id.from_h']), required: false)

      assert_equal "hash['id']&.then { |value| ACP::Types::Id.from_h(value) }", emit.from_expression(converted)
    end

    it 'guards a required checked field over the key guard, at its JSON key' do
      checked = field('note_text', type: type_of(check: [:string]), json: 'noteText')

      assert_equal(
        ["#{check}.string", [["#{check}.key", ['hash', "'noteText'"], nil, nil], "'noteText'"], nil, nil],
        emit.from_expression(checked)
      )
    end

    it 'guards a required nullable checked field over the key guard, allowing nil' do
      checked = field('meta', type: type_of(check: [:string]), nullable: true)

      assert_equal(
        ["#{check}.string", [["#{check}.key", ['hash', "'meta'"], nil, nil], "'meta'", 'allow_nil: true'], nil, nil],
        emit.from_expression(checked)
      )
    end

    it 'guards a clearable checked field at its JSON key, allowing nil and the unset sentinel' do
      string = type_of(check: [:string])
      checked = field('updated_at', type: string, required: false, clearable: true, json: 'updatedAt')
      source = "hash.fetch('updatedAt', :unset)"

      assert_equal(
        ["#{check}.string", [source, "'updatedAt'", 'allow_nil: true', 'allow_unset: true'], nil, nil],
        emit.from_expression(checked)
      )
    end

    it 'guards an optional checked field allowing nil' do
      checked = field('note', type: type_of(check: [:string]), required: false)

      assert_equal(
        ["#{check}.string", ["hash['note']", "'note'", 'allow_nil: true'], nil, nil],
        emit.from_expression(checked)
      )
    end
  end

  describe '.guard' do
    it 'guards a string' do
      assert_equal ["#{check}.string", ['value', "'f'"], nil, nil], emit.guard([:string], 'value', "'f'", false, false)
    end

    it 'guards a boolean' do
      assert_equal(
        ["#{check}.boolean", ['value', "'f'"], nil, nil],
        emit.guard([:boolean], 'value', "'f'", false, false)
      )
    end

    it 'guards an integer within its bounds' do
      assert_equal(
        ["#{check}.integer", ['value', "'f'", 'min: 1', 'max: 100'], nil, nil],
        emit.guard([:integer, 1, 100], 'value', "'f'", false, false)
      )
    end

    it 'guards a number within its bounds' do
      assert_equal(
        ["#{check}.number", ['value', "'f'", 'min: 0.5', 'max: 2.5'], nil, nil],
        emit.guard([:number, 0.5, 2.5], 'value', "'f'", false, false)
      )
    end

    it 'guards an enum against its values' do
      assert_equal(
        ["#{check}.enum", ['value', "'f'", '%w[read write]'], nil, nil],
        emit.guard([:enum, %w[read write]], 'value', "'f'", false, false)
      )
    end

    it 'guards a one_of against its classes, without a block when it has no items' do
      assert_equal(
        ["#{check}.one_of", ['value', "'f'", '[String, Integer]'], nil, nil],
        emit.guard([:one_of, %w[String Integer], nil], 'value', "'f'", false, false)
      )
    end

    it 'guards the items of a one_of in a block over the yielded item and path' do
      items = ['item, path', ["#{check}.string", %w[item path], nil, nil]]

      assert_equal(
        ["#{check}.one_of", ['value', "'f'", '[Array]'], items, nil],
        emit.guard([:one_of, %w[Array], [:string]], 'value', "'f'", false, false)
      )
    end

    it 'guards the values of a hash in a block over the yielded value and path' do
      assert_equal(
        ["#{check}.hash", ['value', "'f'"], ['value, path', ["#{check}.string", %w[value path], nil, nil]], nil],
        emit.guard([:hash, [:string]], 'value', "'f'", false, false)
      )
    end

    it 'guards the items of an array in a block over the yielded item and path' do
      assert_equal(
        ["#{check}.array", ['value', "'f'"], ['item, path', ["#{check}.string", %w[item path], nil, nil]], nil],
        emit.guard([:array, [:string]], 'value', "'f'", false, false)
      )
    end

    it 'guards an object against its constant' do
      assert_equal(
        ["#{check}.object", ['value', "'f'", 'ACP::Types::Step'], nil, nil],
        emit.guard([:object, 'ACP::Types::Step'], 'value', "'f'", false, false)
      )
    end

    it 'guards a list of objects against its constant' do
      assert_equal(
        ["#{check}.objects", ['value', "'f'", 'ACP::Types::AnyList'], nil, nil],
        emit.guard([:objects, 'ACP::Types::AnyList'], 'value', "'f'", false, false)
      )
    end

    it 'appends the nil and unset options after the other arguments of every guard' do
      specs = [
        [:string],
        [:boolean],
        [:integer, 1, nil],
        [:number, 0.5, nil],
        [:enum, %w[read write]],
        [:one_of, %w[String Integer], nil],
        [:hash, [:string]],
        [:array, [:string]],
        [:object, 'ACP::Types::Step'],
        [:objects, 'ACP::Types::AnyList']
      ]

      args = specs.map { |spec| emit.guard(spec, 'value', "'f'", true, true)[1] }

      assert_equal(
        [
          ['value', "'f'"],
          ['value', "'f'"],
          ['value', "'f'", 'min: 1'],
          ['value', "'f'", 'min: 0.5'],
          ['value', "'f'", '%w[read write]'],
          ['value', "'f'", '[String, Integer]'],
          ['value', "'f'"],
          ['value', "'f'"],
          ['value', "'f'", 'ACP::Types::Step'],
          ['value', "'f'", 'ACP::Types::AnyList']
        ].map { |others| [*others, 'allow_nil: true', 'allow_unset: true'] },
        args
      )
    end

    it 'does not extend the options to the guard nested in any container' do
      specs = [[:one_of, %w[Array], [:string]], [:hash, [:string]], [:array, [:string]]]

      blocks = specs.map { |spec| emit.guard(spec, 'value', "'f'", true, true)[2] }

      assert_equal(
        [
          ['item, path', ["#{check}.string", %w[item path], nil, nil]],
          ['value, path', ["#{check}.string", %w[value path], nil, nil]],
          ['item, path', ["#{check}.string", %w[item path], nil, nil]]
        ],
        blocks
      )
    end
  end

  describe '.guard_options' do
    it 'is empty for a field that is neither nilable nor clearable' do
      assert_empty emit.guard_options(false, false)
    end

    it 'allows nil for a nilable field' do
      assert_equal ['allow_nil: true'], emit.guard_options(true, false)
    end

    it 'allows the unset sentinel for a clearable field' do
      assert_equal ['allow_unset: true'], emit.guard_options(false, true)
    end

    it 'allows both, nil first' do
      assert_equal ['allow_nil: true', 'allow_unset: true'], emit.guard_options(true, true)
    end
  end

  describe '.bounds' do
    it 'is empty without bounds' do
      assert_empty emit.bounds(nil, nil)
    end

    it 'names only the lower bound when the upper is absent, keeping a zero' do
      assert_equal ['min: 0'], emit.bounds(0, nil)
    end

    it 'names only the upper bound when the lower is absent' do
      assert_equal ['max: 100'], emit.bounds(nil, 100)
    end

    it 'names both bounds, min first, as numeric literals' do
      assert_equal ['min: -1_000', 'max: 4_294_967_295'], emit.bounds(-1000, 4_294_967_295)
    end
  end

  describe '.numeric' do
    it 'leaves a number of up to three digits alone' do
      assert_equal '100', emit.numeric(100)
    end

    it 'groups the digits of a longer number in threes from the right' do
      literals = [1000, 4_294_967_295, -9_007_199_254_740_991].map { |value| emit.numeric(value) }

      assert_equal %w[1_000 4_294_967_295 -9_007_199_254_740_991], literals
    end
  end

  describe '.enum_values' do
    it 'is a word array for several bare-word strings' do
      assert_equal '%w[read write end-turn]', emit.enum_values(%w[read write end-turn])
    end

    it 'is a bracketed literal for a single value' do
      assert_equal "['read']", emit.enum_values(%w[read])
    end

    it 'is a bracketed literal when a value is not a string' do
      assert_equal "['read', 2]", emit.enum_values(['read', 2])
    end

    it 'is a bracketed literal when a string is not a bare word' do
      assert_equal "['read', 'end turn']", emit.enum_values(['read', 'end turn'])
    end
  end

  describe '.enum_value' do
    it 'renders an integer as a numeric literal' do
      assert_equal '1_000', emit.enum_value(1000)
    end

    it 'single-quotes a string' do
      assert_equal "'read'", emit.enum_value('read')
    end

    it 'escapes the backslashes and single quotes of a string' do
      assert_equal "'it\\'s a\\\\b'", emit.enum_value("it's a\\b")
    end
  end

  describe '.inline' do
    it 'is the string itself for a string expression' do
      assert_equal "hash['note']", emit.inline("hash['note']")
    end

    it 'calls the callee with its inlined arguments' do
      assert_equal "f(g(hash, 'id'), 'id')", emit.inline(['f', [['g', ['hash', "'id'"], nil, nil], "'id'"], nil, nil])
    end

    it 'appends the block in braces' do
      assert_equal 'f(value) { |item, path| g(item, path) }',
                   emit.inline(['f', %w[value], ['item, path', ['g', %w[item path], nil, nil]], nil])
    end

    it 'appends the cast after the call' do
      assert_equal 'f(value) { |item| item } #: Array[String]',
                   emit.inline(['f', %w[value], %w[item item], '#: Array[String]'])
    end
  end

  describe '.piece_block' do
    it 'is the block of a call that takes one' do
      assert_equal %w[item item], emit.piece_block(['f', %w[value], %w[item item], nil])
    end

    it 'is nil for a call without a block' do
      assert_nil emit.piece_block(['f', %w[value], nil, nil])
    end

    it 'is nil for a string expression' do
      assert_nil emit.piece_block("hash['note']")
    end
  end

  describe '.render' do
    it 'stays on one line, between its prefix and suffix, when it ends exactly at the line limit' do
      value = filling(4, 'a = f(),')

      assert_equal ["a = f(#{value}),"], emit.render(['f', [value], nil, nil], 4, 'a = ', ',')
    end

    it 'never breaks a string expression, however long' do
      value = "#{filling(4, '')}x"

      assert_equal [value], emit.render(value, 4)
    end

    it 'opens a do block after the arguments when its head ends exactly at the line limit' do
      value = filling(4, 'a = f() do |item|')
      piece = ['f', [value], %w[item item], '#: Array[String]']

      assert_equal(
        ["a = f(#{value}) do |item|", '  item', 'end #: Array[String],'],
        emit.render(piece, 4, 'a = ', ',')
      )
    end

    it 'opens the do block straight after a callee without arguments' do
      body = "#{filling(4, 'items.map { |item|  }')}x"
      piece = ['items.map', [], ['item', body], nil]

      assert_equal ['items.map do |item|', "  #{body}", 'end'], emit.render(piece, 4)
    end

    it 'measures the body of a do block from two columns further in' do
      fitting = filling(6, 'g()')

      blocks = [fitting, "#{fitting}x"].map do |value|
        emit.render(['f', [], ['item', ['g', [value], nil, nil]], nil], 4)
      end

      assert_equal(
        [
          ['f do |item|', "  g(#{fitting})", 'end'],
          ['f do |item|', '  g(', "    #{fitting}x", '  )', 'end']
        ],
        blocks
      )
    end

    it 'puts one argument per line when a blockless call overflows' do
      value = filling(4, 'a = f(),')
      piece = ['f', [value, 'b'], nil, '#: String']

      assert_equal ['a = f(', "  #{value},", '  b', ') #: String,'], emit.render(piece, 4, 'a = ', ',')
    end

    it 'measures a wrapped argument from two columns further in' do
      fitting = filling(6, 'g()')

      calls = [fitting, "#{fitting}x"].map { |value| emit.render(['f', [['g', [value], nil, nil]], nil, nil], 4) }

      assert_equal [['f(', "  g(#{fitting})", ')'], ['f(', '  g(', "    #{fitting}x", '  )', ')']], calls
    end

    it 'puts one argument per line before the do block when the arguments overflow on their own' do
      value = filling(4, 'a = f() do |item|')
      piece = ['f', [value, 'b'], %w[item item], '#: String']

      assert_equal(
        ['a = f(', "  #{value},", '  b', ') do |item|', '  item', 'end #: String,'],
        emit.render(piece, 4, 'a = ', ',')
      )
    end

    it 'measures the block body after wrapped arguments from two columns further in' do
      arg = "#{filling(4, 'f() do |item|')}x"
      fitting = filling(6, 'g()')

      blocks = [fitting, "#{fitting}x"].map do |value|
        emit.render(['f', [arg], ['item', ['g', [value], nil, nil]], nil], 4)
      end

      assert_equal(
        [
          ['f(', "  #{arg}", ') do |item|', "  g(#{fitting})", 'end'],
          ['f(', "  #{arg}", ') do |item|', '  g(', "    #{fitting}x", '  )', 'end']
        ],
        blocks
      )
    end
  end

  describe '.to_h_method' do
    it 'is an empty hash when there are no fields and no tag' do
      assert_equal ["# @rbs return: #{raw_hash}", 'def to_h', '  {}', 'end'], emit.to_h_method([], nil)
    end

    it 'stamps the tag ahead of the fields' do
      assert_equal "  { 'type' => 'tagged', 'id' => id }", emit.to_h_method([field('id')], %w[type tagged])[2]
    end

    it 'keys each entry by its JSON key, converts nil-safely only where nilable, keeps nils when all are required' do
      fields = [
        field('session_id', json: 'sessionId'),
        field('mode', type: type_of('ACP::Types::Mode', to: [:send, 'to_h'])),
        field('meta', type: type_of('ACP::Types::Meta', to: [:send, 'to_h']), nullable: true)
      ]

      assert_equal(
        "  { 'sessionId' => session_id, 'mode' => mode.to_h, 'meta' => meta&.to_h }",
        emit.to_h_method(fields, nil)[2]
      )
    end

    it 'lists required fields ahead of optional ones and compacts the absent ones away' do
      fields = [field('note', required: false), field('id')]

      assert_equal "  { 'id' => id, 'note' => note }.compact", emit.to_h_method(fields, nil)[2]
    end

    it 'merges required nullable fields back in after compacting, so their nils survive' do
      fields = [field('note', required: false), field('meta', nullable: true), field('id')]

      assert_equal "  { 'id' => id, 'note' => note }.compact.merge('meta' => meta)", emit.to_h_method(fields, nil)[2]
    end

    it 'merges clearable fields in without the unset ones, leaving their nils uncompacted' do
      fields = [field('id'), field('title', required: false, clearable: true)]

      assert_equal(
        "  { 'id' => id }.merge({ 'title' => title }.reject { |_, value| value == :unset })",
        emit.to_h_method(fields, nil)[2]
      )
    end

    it "merges in a flattened field's own hash" do
      fields = [field('id'), field('mode', json: nil, flattened: true)]

      assert_equal "  { 'id' => id }.merge(mode.to_h)", emit.to_h_method(fields, nil)[2]
    end

    it 'chains compact, then nullable, then clearable, then flattened' do
      fields = [
        field('d', json: nil, flattened: true),
        field('c', required: false, clearable: true),
        field('b', nullable: true),
        field('a', required: false)
      ]
      chain = ".compact.merge('b' => b).merge({ 'c' => c }.reject { |_, value| value == :unset }).merge(d.to_h)"

      assert_equal "  { 'a' => a }#{chain}", emit.to_h_method(fields, nil)[2]
    end

    it 'measures the hash from the method body indent' do
      fitting = filling(4, "{ 'j' =>  }")

      openings = [fitting, "#{fitting}x"].map { |attr| emit.to_h_method([field(attr, json: 'j')], nil)[2] }

      assert_equal ["  { 'j' => #{fitting} }", '  {'], openings
    end
  end

  describe '.to_expression' do
    it 'converts a field that is not clearable' do
      mode = field('mode', type: type_of('ACP::Types::Mode', to: [:send, 'to_h']))

      assert_equal 'mode.to_h', emit.to_expression(mode)
    end

    it 'is the bare attribute of a clearable field without a conversion' do
      assert_equal 'title', emit.to_expression(field('title', required: false, clearable: true))
    end

    it 'passes the unset sentinel of a clearable field through unconverted' do
      stamp = field('stamp', type: type_of('ACP::Types::Stamp', to: [:send, 'to_h']), required: false, clearable: true)

      assert_equal 'stamp.is_a?(Symbol) ? stamp : stamp&.to_h', emit.to_expression(stamp)
    end
  end

  describe '.call' do
    it 'is the bare prefix without arguments' do
      assert_equal ['def initialize'], emit.call('def initialize', [], 2)
    end

    it 'stays on one line when it ends exactly at the line limit' do
      arg = filling(2, 'def f(a:, )')

      assert_equal ["def f(a:, #{arg})"], emit.call('def f', ['a:', arg], 2)
    end

    it 'puts one argument per line, comma-separated, once it passes the line limit' do
      arg = "#{filling(2, 'def f(a:, )')}x"

      assert_equal ['def f(', '  a:,', "  #{arg}", ')'], emit.call('def f', ['a:', arg], 2)
    end
  end

  describe '.hash_literal' do
    it 'is empty braces, with the suffix, when there are no entries' do
      assert_equal ['{}.merge(mode.to_h)'], emit.hash_literal([], '.merge(mode.to_h)', 4)
    end

    it 'keeps empty braces on one line even when the suffix passes the line limit' do
      suffix = ".merge(#{filling(4, '{}.merge()')}x)"

      assert_equal ["{}#{suffix}"], emit.hash_literal([], suffix, 4)
    end

    it 'stays on one line when it ends exactly at the line limit' do
      entry = filling(4, "{ 'a' => a,  }.compact")

      assert_equal ["{ 'a' => a, #{entry} }.compact"], emit.hash_literal(["'a' => a", entry], '.compact', 4)
    end

    it 'puts one entry per line, comma-separated, and the suffix on the closing brace once it passes the line limit' do
      entry = "#{filling(4, "{ 'a' => a,  }.compact")}x"

      assert_equal ['{', "  'a' => a,", "  #{entry}", '}.compact'],
                   emit.hash_literal(["'a' => a", entry], '.compact', 4)
    end
  end

  describe '.convert' do
    it 'leaves the expression alone without a conversion' do
      assert_equal 'value', emit.convert(nil, 'value', true)
    end

    it 'guards a call behind a nil-safe then for a nilable expression' do
      assert_equal 'value&.then { |value| Mode.from_h(value) }', emit.convert([:call, 'Mode.from_h'], 'value', true)
    end

    it 'wraps the expression in a call' do
      assert_equal 'Mode.from_h(value)', emit.convert([:call, 'Mode.from_h'], 'value', false)
    end

    it 'sends the method to the expression' do
      assert_equal 'value.to_h', emit.convert([:send, 'to_h'], 'value', false)
    end

    it 'sends the method nil-safely to a nilable expression' do
      assert_equal 'value&.to_h', emit.convert([:send, 'to_h'], 'value', true)
    end

    it 'maps a send over a list with a symbol proc' do
      assert_equal 'value.map(&:to_h)', emit.convert([:map, [:send, 'to_h']], 'value', false)
    end

    it 'transforms the values of a nilable hash nil-safely with a symbol proc' do
      assert_equal 'value&.transform_values(&:to_h)', emit.convert([:transform_values, [:send, 'to_h']], 'value', true)
    end

    it 'maps any other conversion in a block over a non-nil item' do
      assert_equal 'value&.map { |item| Mode.from_h(item) }',
                   emit.convert([:map, [:call, 'Mode.from_h']], 'value', true)
    end

    it 'nests a container conversion inside the block' do
      assert_equal(
        'value.transform_values { |item| item.map(&:to_h) }',
        emit.convert([:transform_values, [:map, [:send, 'to_h']]], 'value', false)
      )
    end
  end

  describe '.optional' do
    it 'leaves untyped alone' do
      assert_equal 'untyped', emit.optional('untyped')
    end

    it 'leaves a union that already admits nil alone' do
      assert_equal 'String | nil', emit.optional('String | nil')
    end

    it 'does not mistake a type whose name contains nil for one that admits it' do
      assert_equal 'Vanilla?', emit.optional('Vanilla')
    end

    it 'parenthesises a union before marking it optional' do
      assert_equal '(String | Integer)?', emit.optional('String | Integer')
    end

    it 'marks a single type optional' do
      assert_equal 'String?', emit.optional('String')
    end
  end
end
