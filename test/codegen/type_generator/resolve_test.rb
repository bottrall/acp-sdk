# frozen_string_literal: true

require 'test_helper'
require_relative '../../../codegen/type_generator'

describe TypeGenerator::Resolve do
  let(:step) { { 'type' => 'object', 'properties' => { 'index' => { 'type' => 'integer' } }, 'required' => ['index'] } }
  let(:note) { { 'type' => 'object', 'properties' => { 'text' => { 'type' => 'string' } }, 'required' => ['text'] } }
  let(:mode) { { 'oneOf' => [{ 'type' => 'string', 'const' => 'read' }, { 'type' => 'string', 'const' => 'write' }] } }
  let(:level) { { 'anyOf' => [{ 'type' => 'string', 'const' => 'low' }, { 'title' => 'Other', 'type' => 'string' }] } }
  let(:choice) do
    {
      'oneOf' => [
        {
          'title' => 'Read', 'type' => 'object',
          'properties' => { 'kind' => { 'type' => 'string', 'const' => 'read' } },
          'required' => ['kind']
        },
        {
          'title' => 'Write', 'type' => 'object',
          'properties' => { 'kind' => { 'type' => 'string', 'const' => 'write' } },
          'required' => ['kind']
        }
      ]
    }
  end
  let(:any_list) do
    {
      'anyOf' => [
        { 'title' => 'Steps', 'type' => 'array', 'items' => { '$ref' => '#/$defs/Step' } },
        { 'title' => 'Notes', 'type' => 'array', 'items' => { '$ref' => '#/$defs/Note' } }
      ]
    }
  end
  let(:amount) { { 'oneOf' => [{ 'type' => 'string' }, { 'type' => 'integer' }] } }
  let(:maybe_tags) do
    {
      'anyOf' => [
        { 'type' => 'boolean' },
        { 'type' => 'array', 'items' => { 'type' => 'string' } },
        { 'type' => 'null' }
      ]
    }
  end
  let(:session_config_option) do
    { 'type' => 'object', 'properties' => { 'id' => { 'type' => 'string' } }, 'required' => ['id'], **choice }
  end
  let(:session_info_update) do
    { 'type' => 'object', 'properties' => { 'title' => { 'type' => 'string' }, 'cwd' => { 'type' => 'string' } } }
  end
  let(:raw_defs) do
    {
      'Step' => step,
      'Note' => note,
      'Mode' => mode,
      'Level' => level,
      'Choice' => choice,
      'AnyList' => any_list,
      'Amount' => amount,
      'MaybeTags' => maybe_tags,
      'Label' => { 'type' => 'string' },
      'SessionConfigOption' => session_config_option,
      'SessionInfoUpdate' => session_info_update
    }
  end
  let(:defs) { TypeGenerator::Schema.new(raw_defs) }
  let(:resolver) { TypeGenerator::Resolve }

  def ref(name) = { '$ref' => "#/$defs/#{name}" }

  def facets(type) = { rbs: type.rbs, from: type.from, to: type.to, check: type.check, nullable: type.nullable? }

  def unconverted(rbs, check) = { rbs:, from: nil, to: nil, check:, nullable: false }

  def field_for(property, json: 'value', **)
    resolver.fields(defs, { 'properties' => { json => property } }, **).fetch(0)
  end

  def field_facets(field)
    {
      json: field.json,
      attr: field.attr,
      type: facets(field.type),
      required: field.required?,
      nullable: field.nullable?,
      clearable: field.clearable?,
      flattened: field.flattened?
    }
  end

  def class_file_call(call)
    name, schema, const, fields = call
    [name, schema, const, fields.map { |field| field_facets(field) }]
  end

  def recording(mod, *names)
    names.each { |name| mod.define_singleton_method(name) { |*args| [name, *args] } }
    yield
  ensure
    names.each { |name| mod.singleton_class.send(:remove_method, name) }
  end

  describe '.variants' do
    it 'reads the oneOf options' do
      assert_equal mode.fetch('oneOf'), resolver.variants(mode)
    end

    it 'falls back to the anyOf options' do
      assert_equal level.fetch('anyOf'), resolver.variants(level)
    end

    it 'is nil for a definition with neither' do
      assert_nil resolver.variants(step)
    end
  end

  describe '.kind' do
    it 'classifies a definition with properties as an object, even alongside variants' do
      assert_equal :object, resolver.kind(session_config_option)
    end

    it 'classifies a definition with neither properties nor variants as a primitive' do
      assert_equal :primitive, resolver.kind({ 'type' => 'string' })
    end

    it 'classifies all-const variants as an enum' do
      assert_equal :enum, resolver.kind(mode)
    end

    it 'classifies const variants alongside a titled catch-all as an enum' do
      assert_equal :enum, resolver.kind(level)
    end

    it 'does not classify a const variant alongside an untitled catch-all as an enum' do
      untitled = { 'oneOf' => [{ 'type' => 'string', 'const' => 'none' }, { 'type' => 'string' }] }

      assert_equal :primitive_union, resolver.kind(untitled)
    end

    it 'does not classify titled variants with no const among them as an enum' do
      titled = { 'oneOf' => [{ 'title' => 'Text', 'type' => 'string' }, { 'title' => 'Count', 'type' => 'integer' }] }

      assert_equal :primitive_union, resolver.kind(titled)
    end

    it 'does not classify a const variant alongside a titled object variant as an enum' do
      mixed = { 'oneOf' => [{ 'type' => 'string', 'const' => 'none' }, { 'title' => 'Some', 'type' => 'object' }] }

      assert_equal :union, resolver.kind(mixed)
    end

    it 'classifies all-array variants as an array union' do
      assert_equal :array_union, resolver.kind(any_list)
    end

    it 'classifies variants with no object among them as a primitive union' do
      assert_equal :primitive_union, resolver.kind(maybe_tags)
    end

    it 'classifies variants with an object among them as a union' do
      assert_equal :union, resolver.kind({ 'anyOf' => [ref('Step'), { 'type' => 'object' }] })
    end
  end

  describe '.object_like?' do
    it 'accepts a schema with properties' do
      assert resolver.object_like?({ 'properties' => {} })
    end

    it 'accepts a schema with allOf' do
      assert resolver.object_like?({ 'allOf' => [ref('Step')] })
    end

    it 'accepts a schema typed as object' do
      assert resolver.object_like?({ 'type' => 'object' })
    end

    it 'rejects any other schema' do
      refute resolver.object_like?({ 'type' => 'string' })
    end
  end

  describe '.definition_files' do
    it 'emits nothing for a def the schema pass does not generate' do
      stable_only = TypeGenerator::Schema.new(raw_defs, twins: ['Note'])

      assert_empty resolver.definition_files(stable_only, 'Step')
    end

    it 'emits the object files of an object def' do
      object_files, definition_files = recording(TypeGenerator::Emit, :class_file) do
        [resolver.object_files(defs, 'Step'), resolver.definition_files(defs, 'Step')]
      end

      assert_equal(
        object_files.map { |call| class_file_call(call) },
        definition_files.map { |call| class_file_call(call) }
      )
    end

    it "emits the union files of a union def under the def's own constant" do
      files = recording(TypeGenerator::Unions, :union_files) { resolver.definition_files(defs, 'Choice') }

      assert_equal [:union_files, defs, defs.const('Choice'), choice], files
    end

    it "emits the array-union file of an array-union def under the def's own constant" do
      files = recording(TypeGenerator::Unions, :array_union_file) { resolver.definition_files(defs, 'AnyList') }

      assert_equal [[:array_union_file, defs, defs.const('AnyList'), any_list]], files
    end

    it "emits the enum file of an enum def under the def's own constant" do
      files = recording(TypeGenerator::Unions, :enum_file) { resolver.definition_files(defs, 'Mode') }

      assert_equal [[:enum_file, defs, defs.const('Mode'), mode]], files
    end

    it 'emits nothing for a primitive def' do
      assert_empty resolver.definition_files(defs, 'Label')
    end

    it 'emits nothing for a primitive-union def' do
      assert_empty resolver.definition_files(defs, 'Amount')
    end
  end

  describe '.resolve' do
    it 'resolves a $ref through the def it names' do
      assert_equal facets(resolver.resolve_ref(defs, 'Step')), facets(resolver.resolve(defs, ref('Step')))
    end

    it 'resolves an allOf wrapper to its option' do
      assert_equal facets(resolver.resolve_ref(defs, 'Step')),
                   facets(resolver.resolve(defs, { 'allOf' => [ref('Step')] }))
    end

    it 'resolves an anyOf wrapper to its first non-null option' do
      assert_equal facets(resolver.resolve_ref(defs, 'Step')),
                   facets(resolver.resolve(defs, { 'anyOf' => [{ 'type' => 'null' }, ref('Step'), ref('Note')] }))
    end

    it 'resolves any other schema inline' do
      schema = { 'type' => 'string' }

      assert_equal facets(resolver.resolve_inline(defs, schema)), facets(resolver.resolve(defs, schema))
    end
  end

  describe '.resolve_inline' do
    it 'maps the item conversions and check over an array' do
      klass = defs.const('Step')

      assert_equal(
        {
          rbs: "Array[#{klass}]",
          from: [:map, [:call, "#{klass}.from_h"]],
          to: [:map, [:send, 'to_h']],
          check: [:array, [:object, klass]],
          nullable: false
        },
        facets(resolver.resolve_inline(defs, { 'type' => 'array', 'items' => ref('Step') }))
      )
    end

    it 'leaves an array unconverted and unchecked when its items need neither' do
      assert_equal unconverted('Array[untyped]', nil),
                   facets(resolver.resolve_inline(defs, { 'type' => 'array', 'items' => {} }))
    end

    it 'resolves an object with no additionalProperties schema to a raw hash' do
      assert_equal unconverted(TypeGenerator::RAW_HASH, nil),
                   facets(resolver.resolve_inline(defs, { 'type' => 'object', 'additionalProperties' => true }))
    end

    it 'maps the value conversions and check over an object with an additionalProperties schema' do
      klass = defs.const('Step')

      assert_equal(
        {
          rbs: "Hash[String, #{klass}]",
          from: [:transform_values, [:call, "#{klass}.from_h"]],
          to: [:transform_values, [:send, 'to_h']],
          check: [:hash, [:object, klass]],
          nullable: false
        },
        facets(resolver.resolve_inline(defs, { 'type' => 'object', 'additionalProperties' => ref('Step') }))
      )
    end

    it 'leaves an object unconverted and unchecked when its values need neither' do
      assert_equal unconverted('Hash[String, untyped]', nil),
                   facets(resolver.resolve_inline(defs, { 'type' => 'object', 'additionalProperties' => {} }))
    end

    it 'resolves a primitive to its RBS type and check, ignoring a null alternative' do
      assert_equal unconverted(TypeGenerator::PRIMITIVES.fetch('string'), [:string]),
                   facets(resolver.resolve_inline(defs, { 'type' => %w[string null] }))
    end

    it 'resolves a schema with no type to untyped' do
      assert_equal unconverted('untyped', nil), facets(resolver.resolve_inline(defs, {}))
    end
  end

  describe '.primitive_check' do
    it 'checks a boolean' do
      assert_equal [:boolean], resolver.primitive_check({ 'type' => 'boolean' }, 'boolean')
    end

    it "checks an integer against the schema's bounds" do
      schema = { 'type' => 'integer', 'minimum' => 1, 'maximum' => 100 }

      assert_equal [:integer, 1, 100], resolver.primitive_check(schema, 'integer')
    end

    it "checks a number against the schema's bounds" do
      schema = { 'type' => 'number', 'minimum' => 0.5, 'maximum' => 2.5 }

      assert_equal [:number, 0.5, 2.5], resolver.primitive_check(schema, 'number')
    end

    it 'checks anything else as a string' do
      assert_equal [:string], resolver.primitive_check({ 'type' => 'string' }, 'string')
    end
  end

  describe '.resolve_ref' do
    it 'resolves an object def to its class' do
      klass = defs.const('Step')

      assert_equal(
        { rbs: klass, from: [:call, "#{klass}.from_h"], to: [:send, 'to_h'], check: [:object, klass], nullable: false },
        facets(resolver.resolve_ref(defs, 'Step'))
      )
    end

    it 'resolves a union def to the type alias of its module' do
      klass = defs.const('Choice')

      assert_equal(
        {
          rbs: "#{klass}::t",
          from: [:call, "#{klass}.from_h"],
          to: [:send, 'to_h'],
          check: [:object, klass],
          nullable: false
        },
        facets(resolver.resolve_ref(defs, 'Choice'))
      )
    end

    it 'resolves an array-union def to the type alias of its module, converted elementwise' do
      klass = defs.const('AnyList')

      assert_equal(
        {
          rbs: "#{klass}::t",
          from: [:call, "#{klass}.from_a"],
          to: [:map, [:send, 'to_h']],
          check: [:objects, klass],
          nullable: false
        },
        facets(resolver.resolve_ref(defs, 'AnyList'))
      )
    end

    it 'resolves a closed enum def to its primitive, checked against the const values' do
      assert_equal unconverted(TypeGenerator::PRIMITIVES.fetch('string'), [:enum, %w[read write]]),
                   facets(resolver.resolve_ref(defs, 'Mode'))
    end

    it 'leaves an open enum def unchecked' do
      assert_equal unconverted(TypeGenerator::PRIMITIVES.fetch('string'), nil),
                   facets(resolver.resolve_ref(defs, 'Level'))
    end

    it 'resolves a primitive-union def to a one_of check over the variant classes' do
      rbs = TypeGenerator::PRIMITIVES.values_at('string', 'integer').join(' | ')
      classes = TypeGenerator::RUBY_CLASSES.values_at('string', 'integer').flatten

      assert_equal unconverted(rbs, [:one_of, classes, nil]), facets(resolver.resolve_ref(defs, 'Amount'))
    end

    it 'makes a primitive union with a null variant nullable' do
      boolean, string = TypeGenerator::PRIMITIVES.values_at('boolean', 'string')
      type = resolver.resolve_ref(defs, 'MaybeTags')

      assert_equal ["#{boolean} | Array[#{string}] | nil", true], [type.rbs, type.nullable?]
    end

    it "passes one_of the item check of a primitive union's array variant" do
      classes = [*TypeGenerator::RUBY_CLASSES.fetch('boolean'), 'Array']

      assert_equal [:one_of, classes, [:string]], resolver.resolve_ref(defs, 'MaybeTags').check
    end

    it 'resolves a primitive def through its own schema' do
      assert_equal facets(resolver.resolve(defs, raw_defs.fetch('Label'))), facets(resolver.resolve_ref(defs, 'Label'))
    end
  end

  describe '.elementwise' do
    it 'wraps a conversion in the given method' do
      assert_equal [:map, [:send, 'to_h']], resolver.elementwise(:map, [:send, 'to_h'])
    end

    it 'stays nil when there is no conversion' do
      assert_nil resolver.elementwise(:map, nil)
    end
  end

  describe '.fields' do
    it 'yields no fields for a schema with no properties' do
      assert_empty resolver.fields(defs, { 'type' => 'object' })
    end

    it 'skips the excepted properties' do
      fields = resolver.fields(defs, { 'properties' => { 'kind' => {}, 'index' => {} } }, except: ['kind'])

      assert_equal ['index'], fields.map(&:json)
    end

    it "resolves each property's type" do
      assert_equal facets(resolver.resolve(defs, ref('Step'))), facets(field_for(ref('Step')).type)
    end

    it 'marks a property with no declared type nullable' do
      assert_predicate field_for({ 'description' => 'anything' }), :nullable?
    end

    it 'marks a property whose resolved type is nullable as nullable' do
      assert_predicate field_for(ref('MaybeTags')), :nullable?
    end

    it 'marks a property whose type list includes null as nullable' do
      assert_predicate field_for({ 'type' => %w[string null] }), :nullable?
    end

    it 'marks a property with a null anyOf option as nullable' do
      assert_predicate field_for({ 'anyOf' => [ref('Step'), { 'type' => 'null' }] }), :nullable?
    end

    it 'leaves any other property non-nullable' do
      refute_predicate field_for({ 'type' => 'string' }), :nullable?
    end

    it 'names the attr after the snake-cased JSON key, which it keeps as spelled' do
      field = field_for({ 'type' => 'string' }, json: 'updatedAt')

      assert_equal ['updatedAt', TypeGenerator::Plan.snake('updatedAt')], [field.json, field.attr]
    end

    it 'suffixes an attr that would be a Ruby keyword with an underscore' do
      assert_equal "#{TypeGenerator::Plan.snake('class')}_", field_for({ 'type' => 'string' }, json: 'class').attr
    end

    it 'marks the properties the schema lists as required' do
      fields = resolver.fields(defs, { 'properties' => { 'id' => {}, 'name' => {} }, 'required' => ['id'] })

      assert_equal [true, false], fields.map(&:required?)
    end

    it 'treats every property as optional when the schema lists none as required' do
      refute_predicate field_for({ 'type' => 'string' }), :required?
    end

    it 'marks the listed properties clearable' do
      assert_predicate field_for({ 'type' => 'string' }, clearable: ['value']), :clearable?
    end

    it 'leaves the unlisted properties unclearable' do
      refute_predicate field_for({ 'type' => 'string' }, clearable: ['other']), :clearable?
    end
  end

  describe '.object_fields' do
    it "yields the def's own fields, clearable where the def is listed as clearing them" do
      listed = TypeGenerator::CLEARABLE.fetch('SessionInfoUpdate')
      fields = resolver.object_fields(defs, 'SessionInfoUpdate')

      expected = session_info_update.fetch('properties').keys.to_h { |json| [json, listed.include?(json)] }

      assert_equal(expected, fields.to_h { |field| [field.json, field.clearable?] })
    end

    it 'appends a required flattened field named for the def to a def with variants' do
      flattened = resolver.object_fields(defs, 'SessionConfigOption').last

      assert_equal(
        {
          attr: TypeGenerator::FLATTENED_UNION_ATTRS.fetch('SessionConfigOption'),
          flattened: true,
          required: true,
          nullable: false
        },
        {
          attr: flattened.attr,
          flattened: flattened.flattened?,
          required: flattened.required?,
          nullable: flattened.nullable?
        }
      )
    end

    it 'types the flattened field as the flattened union, left unchecked' do
      union = resolver.flattened_union(defs, 'SessionConfigOption')

      assert_equal(
        { rbs: "#{union}::t", from: [:call, "#{union}.from_h"], to: [:send, 'to_h'], check: nil, nullable: false },
        facets(resolver.object_fields(defs, 'SessionConfigOption').last.type)
      )
    end

    it "keeps the def's own fields ahead of the flattened one in a def with variants" do
      assert_equal ['id', nil], resolver.object_fields(defs, 'SessionConfigOption').map(&:json)
    end
  end

  describe '.object_files' do
    it "emits only the class file of a def without variants, under the def's own constant with its object fields" do
      fields = resolver.object_fields(defs, 'Step').map { |field| field_facets(field) }
      files = recording(TypeGenerator::Emit, :class_file) { resolver.object_files(defs, 'Step') }

      assert_equal([[:class_file, defs, defs.const('Step'), fields]], files.map { |call| class_file_call(call) })
    end

    it 'follows the class file of a def with variants with the files of its flattened union' do
      fields = resolver.object_fields(defs, 'SessionConfigOption').map { |field| field_facets(field) }
      class_file, *union_files = recording(TypeGenerator::Emit, :class_file) do
        recording(TypeGenerator::Unions, :union_files) { resolver.object_files(defs, 'SessionConfigOption') }
      end

      assert_equal(
        [
          [:class_file, defs, defs.const('SessionConfigOption'), fields],
          :union_files, defs, resolver.flattened_union(defs, 'SessionConfigOption'), session_config_option
        ],
        [class_file_call(class_file), *union_files]
      )
    end
  end

  describe '.union_const' do
    it "is a union def's own constant" do
      assert_equal defs.const('Choice'), resolver.union_const(defs, 'Choice')
    end

    it 'is the flattened union of an object def with variants' do
      assert_equal resolver.flattened_union(defs, 'SessionConfigOption'),
                   resolver.union_const(defs, 'SessionConfigOption')
    end

    it 'is nil for an object def without variants' do
      assert_nil resolver.union_const(defs, 'Step')
    end

    it 'is nil for any other kind of def' do
      assert_nil resolver.union_const(defs, 'Mode')
    end
  end

  describe '.flattened_union' do
    let(:nested) { TypeGenerator::Plan.camel(TypeGenerator::FLATTENED_UNION_ATTRS.fetch('SessionConfigOption')) }

    it "nests the camel-cased flattened attr under the def's own constant" do
      assert_equal "#{defs.const('SessionConfigOption')}::#{nested}",
                   resolver.flattened_union(defs, 'SessionConfigOption')
    end

    it 'nests it under the variant constant that subsumed the def' do
      subsumed = defs.with_subsumed('SessionConfigOption' => 'ACP::Types::Host::Option')

      assert_equal "ACP::Types::Host::Option::#{nested}", resolver.flattened_union(subsumed, 'SessionConfigOption')
    end
  end
end
