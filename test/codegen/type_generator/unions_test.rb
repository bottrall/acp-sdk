# frozen_string_literal: true

require 'test_helper'
require_relative '../../../codegen/type_generator'

describe TypeGenerator::Unions do
  unions = TypeGenerator::Unions
  emit = TypeGenerator::Emit
  plan = TypeGenerator::Plan
  ref = ->(name) { { '$ref' => "#/$defs/#{name}" } }
  const = ->(value) { { 'type' => 'string', 'const' => value } }
  object = lambda do |key|
    { 'type' => 'object', 'properties' => { key => { 'type' => 'string' } }, 'required' => [key] }
  end
  schema = TypeGenerator::Schema.new(
    {
      'Note' => object.call('text'),
      'Step' => object.call('index'),
      'Mug' => object.call('oz'),
      'Bare' => { 'type' => 'object' },
      'Mode' => { 'oneOf' => [const.call('read'), const.call('write')] }
    },
    header: "# header\n"
  )

  describe '.discriminator' do
    it 'raises when the options carry consts under different properties' do
      options = [{ 'properties' => { 'kind' => const.call('a') } }, { 'properties' => { 'type' => const.call('b') } }]

      error = assert_raises(RuntimeError) { unions.discriminator(options) }

      assert_match(/\AAmbiguous discriminator/, error.message)
    end

    it 'returns the one property the options carry a const under' do
      options = [
        { 'properties' => { 'kind' => const.call('a'), 'text' => { 'type' => 'string' } } },
        { 'properties' => { 'kind' => const.call('b') } }
      ]

      assert_equal 'kind', unions.discriminator(options)
    end

    it 'returns nil when no option carries a const, with or without properties' do
      assert_nil unions.discriminator([{ 'properties' => { 'text' => { 'type' => 'string' } } }, ref.call('Note')])
    end
  end

  describe '.union_files' do
    it 'emits the union module, then each tagged class stamped with its tag, then each untagged class' do
      union = 'ACP::Types::Blend'
      tagged_const = "#{union}::#{plan.camel('tagged')}"
      tagged = { 'title' => 'Tagged', 'properties' => { 'type' => const.call('tagged') }, 'required' => ['type'] }
      plain = { 'title' => 'Plain', 'properties' => { 'note' => { 'type' => 'string' } }, 'required' => ['note'] }
      dispatch = TypeGenerator::Dispatch.new(
        tag: 'type',
        tagged: [['tagged', tagged_const]],
        untagged: [["#{union}::Plain", 'note']]
      )

      assert_equal(
        [
          unions.union_file(schema, union, dispatch),
          emit.class_file(schema, tagged_const, unions.variant_fields(schema, tagged, 'type'), tag: %w[type tagged]),
          emit.class_file(schema, "#{union}::Plain", unions.variant_fields(schema, plain, 'type'))
        ],
        unions.union_files(schema, union, { 'oneOf' => [tagged, plain] })
      )
    end

    it 'emits no class for an untagged variant that is another def, and keys each variant on its required key' do
      union = 'ACP::Types::Pick'
      inline = { 'title' => 'Inline', 'properties' => { 'flag' => { 'type' => 'string' } }, 'required' => ['flag'] }
      dispatch = TypeGenerator::Dispatch.new(
        tag: nil,
        tagged: [],
        untagged: [['ACP::Types::Note', 'text'], ["#{union}::Inline", 'flag']]
      )

      assert_equal(
        [
          unions.union_file(schema, union, dispatch),
          emit.class_file(schema, "#{union}::Inline", unions.variant_fields(schema, inline, nil))
        ],
        unions.union_files(schema, union, { 'anyOf' => [{ 'allOf' => [ref.call('Note')] }, inline] })
      )
    end
  end

  describe '.variant_consts' do
    it 'drops the not options' do
      tagged = { 'properties' => { 'type' => const.call('tagged') } }

      assert_equal(
        ['type', [[tagged, "ACP::Types::Blend::#{plan.camel('tagged')}"]], []],
        unions.variant_consts(schema, 'ACP::Types::Blend', { 'oneOf' => [tagged, { 'not' => {} }] })
      )
    end

    it 'names the options carrying the tag after its value and the rest after their title' do
      tagged = { 'properties' => { 'type' => const.call('tagged') } }
      plain = { 'title' => 'Plain', 'properties' => { 'note' => { 'type' => 'string' } } }

      assert_equal(
        ['type', [[tagged, "ACP::Types::Blend::#{plan.camel('tagged')}"]], [[plain, 'ACP::Types::Blend::Plain']]],
        unions.variant_consts(schema, 'ACP::Types::Blend', { 'oneOf' => [tagged, plain] })
      )
    end

    it 'treats every option as untagged when there is no discriminator' do
      first = { 'title' => 'First' }
      second = { 'title' => 'Second' }

      assert_equal(
        [nil, [], [[first, 'ACP::Types::Pick::First'], [second, 'ACP::Types::Pick::Second']]],
        unions.variant_consts(schema, 'ACP::Types::Pick', { 'anyOf' => [first, second] })
      )
    end
  end

  describe '.subsumes_ref?' do
    it 'holds for an option with its own properties and an allOf ref' do
      assert unions.subsumes_ref?({ 'properties' => {}, 'allOf' => [ref.call('Mug')] })
    end

    it 'fails for an option with no properties' do
      refute unions.subsumes_ref?({ 'allOf' => [ref.call('Mug')] })
    end

    it 'fails for a not option' do
      refute unions.subsumes_ref?({ 'properties' => {}, 'allOf' => [ref.call('Mug')], 'not' => {} })
    end

    it 'fails for an option with no allOf ref' do
      refute unions.subsumes_ref?({ 'properties' => {} })
    end
  end

  describe '.variant_refs' do
    it 'pairs each subsumed def with the variant class that absorbs it' do
      cup = { 'properties' => { 'type' => const.call('cup') }, 'allOf' => [ref.call('Mug')] }

      assert_equal [['Mug', "ACP::Types::Vessel::#{plan.camel('cup')}"]],
                   unions.variant_refs(schema, 'ACP::Types::Vessel', { 'oneOf' => [cup] })
    end

    it 'skips the variants with no ref and the ones that are only a ref' do
      jar = { 'properties' => { 'type' => const.call('jar') } }
      definition = { 'oneOf' => [jar, { 'allOf' => [ref.call('Note')] }] }

      assert_empty unions.variant_refs(schema, 'ACP::Types::Vessel', definition)
    end
  end

  describe '.variant_names' do
    it 'names each option after its tag value' do
      options = %w[read write].map { |value| { 'properties' => { 'type' => const.call(value) } } }

      assert_equal %w[read write].map { |value| plan.camel(value) }, unions.variant_names(options, 'type')
    end

    it 'names every option after its ref when one tag value would shadow a core class' do
      options = [
        { 'properties' => { 'type' => const.call('string') }, 'allOf' => [ref.call('TextBody')] },
        { 'properties' => { 'type' => const.call('image') }, 'allOf' => [ref.call('ImageBody')] }
      ]

      assert_equal %w[TextBody ImageBody], unions.variant_names(options, 'type')
    end
  end

  describe '.variant_ref' do
    it 'returns nil for an option with no allOf' do
      assert_nil unions.variant_ref({ 'properties' => {} })
    end

    it 'returns the def the first allOf entry refers to' do
      assert_equal 'Mug', unions.variant_ref({ 'allOf' => [ref.call('Mug'), ref.call('Note')] })
    end
  end

  describe '.variant_fields' do
    it 'leaves the tag out of the inline fields' do
      option = { 'properties' => { 'type' => const.call('cup'), 'label' => { 'type' => 'string' } } }

      assert_equal ['label'], unions.variant_fields(schema, option, 'type').map(&:json)
    end

    it 'keeps every inline field when there is no tag' do
      option = { 'properties' => { 'type' => { 'type' => 'string' }, 'label' => { 'type' => 'string' } } }

      assert_equal %w[type label], unions.variant_fields(schema, option, nil).map(&:json)
    end

    it 'appends the fields of the def the option refs' do
      option = {
        'properties' => { 'type' => const.call('cup'), 'label' => { 'type' => 'string' } },
        'allOf' => [ref.call('Mug')]
      }

      assert_equal %w[label oz], unions.variant_fields(schema, option, 'type').map(&:json)
    end
  end

  describe '.untagged_const' do
    it 'is the refed def itself for an option that is only a ref to an object def' do
      option = { 'allOf' => [ref.call('Note')] }

      assert_equal 'ACP::Types::Note', unions.untagged_const(schema, 'ACP::Types::Pick', option)
    end

    it 'is a class under the union, named after the title, for an option with no ref' do
      assert_equal "ACP::Types::Pick::#{plan.camel('inline item')}",
                   unions.untagged_const(schema, 'ACP::Types::Pick', { 'title' => 'inline item' })
    end

    it 'is a class under the union for a ref option with its own properties' do
      option = { 'title' => 'Inline', 'properties' => {}, 'allOf' => [ref.call('Note')] }

      assert_equal 'ACP::Types::Pick::Inline', unions.untagged_const(schema, 'ACP::Types::Pick', option)
    end

    it 'is a class under the union for a ref to a def that is not an object' do
      option = { 'title' => 'Inline', 'allOf' => [ref.call('Mode')] }

      assert_equal 'ACP::Types::Pick::Inline', unions.untagged_const(schema, 'ACP::Types::Pick', option)
    end
  end

  describe '.required_keys' do
    it 'is empty for an option that requires nothing' do
      assert_empty unions.required_keys(schema, {})
    end

    it 'returns the keys the option itself requires' do
      assert_equal %w[a b], unions.required_keys(schema, { 'required' => %w[a b] })
    end

    it 'appends the keys the refed def requires' do
      assert_equal %w[a oz], unions.required_keys(schema, { 'required' => ['a'], 'allOf' => [ref.call('Mug')] })
    end

    it 'appends nothing for a refed def that requires nothing' do
      assert_equal ['a'], unions.required_keys(schema, { 'required' => ['a'], 'allOf' => [ref.call('Bare')] })
    end
  end

  describe '.unique_keys' do
    it 'raises when a key set has no key of its own' do
      error = assert_raises(RuntimeError) { unions.unique_keys([%w[a b], ['a']]) }

      assert_match(/\ANo distinguishing key/, error.message)
    end

    it 'picks for each key set its first key that no other set has' do
      assert_equal %w[a d], unions.unique_keys([%w[b a c], %w[b d]])
    end
  end

  describe '.union_file' do
    it 'writes the module to the union path, aliasing t to the tagged, untagged, and raw variants ahead of from_h' do
      dispatch = TypeGenerator::Dispatch.new(tag: 'kind', tagged: [%w[read Read]], untagged: [%w[Plain note]])

      assert_equal(
        [
          plan.path('ACP::Types::Choice'),
          emit.source(
            'module ACP::Types::Choice',
            [
              ['# @rbs!', '#   type t = Read', '#          | Plain', '#          | Hash[String, untyped]'],
              [
                '# @rbs hash: Hash[String, untyped]',
                '# @rbs return: t',
                'def self.from_h(hash)',
                "  case hash['kind']",
                "  when 'read' then Read.from_h(hash)",
                '  when nil then Plain.from_h(hash)',
                '  else hash',
                '  end',
                'end'
              ]
            ],
            "# header\n"
          )
        ],
        unions.union_file(schema, 'ACP::Types::Choice', dispatch)
      )
    end
  end

  describe '.type_alias' do
    it 'aliases t to a single type' do
      assert_equal ['# @rbs!', '#   type t = A'], unions.type_alias(['A'])
    end

    it 'continues each further type on its own line' do
      assert_equal ['# @rbs!', '#   type t = A', '#          | B', '#          | C'], unions.type_alias(%w[A B C])
    end
  end

  describe '.dispatch_body' do
    it 'dispatches an untagged union on the presence of each variant key, falling back to the hash' do
      dispatch = TypeGenerator::Dispatch.new(tag: nil, tagged: [], untagged: [%w[First a], %w[Second b]])

      assert_equal(
        [
          "if hash.key?('a')",
          '  First.from_h(hash)',
          "elsif hash.key?('b')",
          '  Second.from_h(hash)',
          'else',
          '  hash',
          'end'
        ],
        unions.dispatch_body(dispatch)
      )
    end

    it 'raises when a tagged union has several untagged variants' do
      untagged = [%w[First a], %w[Second b]]
      dispatch = TypeGenerator::Dispatch.new(tag: 'kind', tagged: [%w[read Read]], untagged:)

      error = assert_raises(RuntimeError) { unions.dispatch_body(dispatch) }

      assert_match(/\ASeveral untagged variants alongside kind/, error.message)
    end

    it 'dispatches a tagged union on each tag value, falling back to the hash' do
      dispatch = TypeGenerator::Dispatch.new(tag: 'kind', tagged: [%w[read Read], %w[write Write]], untagged: [])

      assert_equal(
        [
          "case hash['kind']",
          "when 'read' then Read.from_h(hash)",
          "when 'write' then Write.from_h(hash)",
          'else hash',
          'end'
        ],
        unions.dispatch_body(dispatch)
      )
    end

    it 'routes a missing tag to the one untagged variant' do
      dispatch = TypeGenerator::Dispatch.new(tag: 'kind', tagged: [%w[read Read]], untagged: [%w[Plain note]])

      assert_equal(
        [
          "case hash['kind']",
          "when 'read' then Read.from_h(hash)",
          'when nil then Plain.from_h(hash)',
          'else hash',
          'end'
        ],
        unions.dispatch_body(dispatch)
      )
    end
  end

  describe '.key_dispatch' do
    it 'opens with if, continues with elsif, indents each result, and ends on the fallback' do
      assert_equal(
        ['if a?', '  one', '  two', 'elsif b?', '  three', 'else', '  rest', 'end'],
        unions.key_dispatch([['a?', %w[one two]], ['b?', ['three']]], 'rest')
      )
    end
  end

  describe '.array_union_file' do
    array_union = ->(names) { { 'anyOf' => names.map { |name| { 'type' => 'array', 'items' => ref.call(name) } } } }

    it 'raises when an item def requires no key to tell it apart by' do
      error = assert_raises(RuntimeError) do
        unions.array_union_file(schema, 'ACP::Types::AnyList', array_union.call(%w[Step Bare]))
      end

      assert_match(/\ANo distinguishing key/, error.message)
    end

    it 'writes a module aliasing t to each item array, with from_a dispatching on each item class required key' do
      checked = lambda do |klass|
        emit.indent(
          emit.render(
            ['items.each_with_index.map', [],
             ['item, index', ['ACP::Types::Check.object', ['item', '[index]', klass], nil, nil]],
             "#: Array[#{klass}]"],
            6
          ),
          2
        )
      end

      assert_equal(
        [
          plan.path('ACP::Types::AnyList'),
          emit.source(
            'module ACP::Types::AnyList',
            [
              [
                '# @rbs!',
                '#   type t = Array[ACP::Types::Step]',
                '#          | Array[ACP::Types::Note]',
                '#          | Array[Hash[String, untyped]]'
              ],
              [
                '# @rbs items: Array[Hash[String, untyped]]',
                '# @rbs return: t',
                'def self.from_a(items)',
                *emit.indent(
                  [
                    "if items.all? { |item| item.key?('index') }",
                    *checked.call('ACP::Types::Step'),
                    "elsif items.all? { |item| item.key?('text') }",
                    *checked.call('ACP::Types::Note'),
                    'else',
                    '  items',
                    'end'
                  ],
                  2
                ),
                'end'
              ]
            ],
            "# header\n"
          )
        ],
        unions.array_union_file(schema, 'ACP::Types::AnyList', array_union.call(%w[Step Note]))
      )
    end
  end

  describe '.enum_file' do
    enum_source = lambda do |constants|
      [plan.path('ACP::Types::Mode'), emit.source('module ACP::Types::Mode', [constants], "# header\n")]
    end

    it 'skips the open variant that carries no const' do
      definition = { 'anyOf' => [const.call('read'), { 'type' => 'string', 'title' => 'Other' }] }

      assert_equal enum_source.call(["READ = 'read'"]), unions.enum_file(schema, 'ACP::Types::Mode', definition)
    end

    it 'names each string constant after its value, with runs of other characters as underscores' do
      definition = { 'oneOf' => [const.call('read'), const.call('in-progress / done')] }

      assert_equal enum_source.call(["READ = 'read'", "IN_PROGRESS_DONE = 'in-progress / done'"]),
                   unions.enum_file(schema, 'ACP::Types::Mode', definition)
    end

    it 'names a non-string constant after its title and writes the value bare' do
      definition = { 'oneOf' => [{ 'type' => 'integer', 'const' => 1, 'title' => 'First item' }] }

      assert_equal enum_source.call(['FIRST_ITEM = 1']), unions.enum_file(schema, 'ACP::Types::Mode', definition)
    end
  end
end
