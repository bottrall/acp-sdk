# frozen_string_literal: true

module TypeGenerator::Resolve
  extend self

  # @rbs definition: Hash[String, untyped]
  # @rbs return: untyped
  def variants(definition) = definition['oneOf'] || definition['anyOf']

  # @rbs definition: Hash[String, untyped]
  # @rbs return: Symbol
  def kind(definition)
    options = variants(definition)
    if definition.key?('properties') then :object
    elsif options.nil? then :primitive
    elsif options.all? { |option| option.key?('const') || (!object_like?(option) && option.key?('title')) } &&
          options.any? { |option| option.key?('const') }
      :enum
    elsif options.all? { |option| option['type'] == 'array' } then :array_union
    elsif options.none? { |option| object_like?(option) } then :primitive_union
    else :union
    end
  end

  # @rbs schema: Hash[String, untyped]
  # @rbs return: bool
  def object_like?(schema) = schema.key?('properties') || schema.key?('allOf') || schema['type'] == 'object'

  # @rbs defs: TypeGenerator::Schema
  # @rbs name: String
  # @rbs return: Array[TypeGenerator::file]
  def definition_files(defs, name)
    return [] unless defs.generated?(name)

    definition = defs.fetch(name)
    case kind(definition)
    when :object then object_files(defs, name)
    when :union then TypeGenerator::Unions.union_files(defs, defs.const(name), definition)
    when :array_union then [TypeGenerator::Unions.array_union_file(defs, defs.const(name), definition)]
    when :enum then [TypeGenerator::Unions.enum_file(defs, defs.const(name), definition)]
    else []
    end
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs schema: Hash[String, untyped]
  # @rbs return: TypeGenerator::Type
  def resolve(defs, schema)
    if (ref = schema['$ref']) then resolve_ref(defs, TypeGenerator::Plan.ref_name(ref))
    elsif (options = schema['allOf'] || schema['anyOf'])
      resolve(defs, options.find { |option| option['type'] != 'null' })
    else
      resolve_inline(defs, schema)
    end
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs schema: Hash[String, untyped]
  # @rbs return: TypeGenerator::Type
  def resolve_inline(defs, schema)
    # Steep 2.1 rejects pattern matching as unsupported syntax and leaves this
    # case unchecked.
    case Array(schema['type']) - ['null'] # steep:ignore UnsupportedSyntax
    in ['array']
      item = resolve(defs, schema.fetch('items'))
      TypeGenerator::Type.new(
        rbs: "Array[#{item.rbs}]",
        from: elementwise(:map, item.from),
        to: elementwise(:map, item.to),
        check: item.check && [:array, item.check]
      )
    in ['object']
      values = schema['additionalProperties']
      return TypeGenerator::Type.new(rbs: TypeGenerator::RAW_HASH) unless values.is_a?(Hash)

      value = resolve(defs, values)
      TypeGenerator::Type.new(
        rbs: "Hash[String, #{value.rbs}]",
        from: elementwise(:transform_values, value.from),
        to: elementwise(:transform_values, value.to),
        check: value.check && [:hash, value.check]
      )
    in [type]
      TypeGenerator::Type.new(rbs: TypeGenerator::PRIMITIVES.fetch(type), check: primitive_check(schema, type))
    in [] then TypeGenerator::Type.new(rbs: 'untyped')
    end
  end

  # @rbs schema: Hash[String, untyped]
  # @rbs type: String
  # @rbs return: TypeGenerator::check
  def primitive_check(schema, type)
    case type
    when 'boolean' then [:boolean]
    when 'integer' then [:integer, schema['minimum'], schema['maximum']]
    when 'number' then [:number, schema['minimum'], schema['maximum']]
    else [:string]
    end
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs name: String
  # @rbs return: TypeGenerator::Type
  def resolve_ref(defs, name)
    definition = defs.fetch(name)
    case kind(definition)
    when :object
      klass = defs.const(name)
      TypeGenerator::Type.new(
        rbs: klass,
        from: [:call, "#{klass}.from_h"],
        to: [:send, 'to_h'],
        check: [:object, klass]
      )
    when :union
      klass = defs.const(name)
      TypeGenerator::Type.new(
        rbs: "#{klass}::t",
        from: [:call, "#{klass}.from_h"],
        to: [:send, 'to_h'],
        check: [:object, klass]
      )
    when :array_union
      klass = defs.const(name)
      TypeGenerator::Type.new(
        rbs: "#{klass}::t",
        from: [:call, "#{klass}.from_a"],
        to: [:map, [:send, 'to_h']],
        check: [:objects, klass]
      )
    when :enum
      options = variants(definition)
      rbs = TypeGenerator::PRIMITIVES.fetch(options.first.fetch('type'))
      # An open enum's non-const variant accepts unknown values; a closed one
      # rejects them.
      closed = options.all? { |option| option.key?('const') }
      TypeGenerator::Type.new(rbs:, check: closed ? [:enum, options.map { |option| option.fetch('const') }] : nil)
    when :primitive_union then primitive_union(defs, name, variants(definition))
    else resolve(defs, definition)
    end
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs name: String
  # @rbs options: Array[Hash[String, untyped]]
  # @rbs return: TypeGenerator::Type
  def primitive_union(defs, name, options)
    schemas = options.map { |option| dereference(defs, option) }
    present = schemas.reject { |schema| schema['type'] == 'null' }
    classes = present.flat_map do |schema|
      type, *others = Array(schema['type']) - ['null']
      (TypeGenerator::RUBY_CLASSES[type] if others.empty?) ||
        raise("Unsupported union shape in #{name}: #{schema} is neither a primitive nor an array")
    end
    arrays = present.select { |schema| Array(schema['type']).include?('array') }.map { |schema| resolve(defs, schema) }
    raise "Unsupported union shape in #{name}: several array options" if arrays.size > 1
    raise "Unsupported union shape in #{name}: array items need conversion" if arrays.any?(&:from)

    types = schemas.flat_map do |schema|
      if schema['type'] == 'null' then ['nil']
      else [resolve(defs, schema).rbs, *('nil' if Array(schema['type']).include?('null'))]
      end
    end.uniq
    # A typed-array variant's items are checked by one_of after the Array
    # class matches, so the spec passes the inner item check, not [:array, ...].
    array_check = arrays.first&.check #: [:array, TypeGenerator::check]?
    TypeGenerator::Type.new(
      rbs: types.join(' | '),
      nullable: types.include?('nil'),
      check: [:one_of, classes, array_check&.last]
    )
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs schema: Hash[String, untyped]
  # @rbs return: Hash[String, untyped]
  def dereference(defs, schema)
    ref = schema['$ref']
    return schema unless ref

    definition = defs.fetch(TypeGenerator::Plan.ref_name(ref))
    # A non-primitive def has no type for primitive_union to accept, so its
    # ref is left for the caller to reject.
    kind(definition) == :primitive ? dereference(defs, definition) : schema
  end

  # @rbs method: :map | :transform_values
  # @rbs conversion: TypeGenerator::conversion?
  # @rbs return: TypeGenerator::conversion?
  def elementwise(method, conversion) = conversion && [method, conversion]

  # @rbs defs: TypeGenerator::Schema
  # @rbs schema: Hash[String, untyped]
  # @rbs except: Array[String]
  # @rbs clearable: Array[String]
  # @rbs return: Array[TypeGenerator::Field]
  def fields(defs, schema, except: [], clearable: [])
    required = schema.fetch('required', [])
    properties = schema['properties'] || {} #: Hash[String, Hash[String, untyped]]
    properties.except(*except).map do |json, property|
      type = resolve(defs, property)
      # A property with no declared type accepts any JSON value, null included,
      # so its nil must survive the optional fields' compaction in to_h.
      untyped = TypeGenerator::TYPELESS_PROPERTY_KEYS.none? { |key| property.key?(key) }
      any_of = Array(property['anyOf']) #: Array[Hash[String, untyped]]
      nullable = untyped || type.nullable? || Array(property['type']).include?('null') ||
                 any_of.any? { |option| option['type'] == 'null' }
      name = TypeGenerator::Plan.snake(json)
      attr = TypeGenerator::RUBY_KEYWORDS.include?(name) ? "#{name}_" : name
      TypeGenerator::Field.new(
        json:,
        attr:,
        type:,
        required: required.include?(json),
        nullable:,
        clearable: clearable.include?(json)
      )
    end
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs name: String
  # @rbs return: Array[TypeGenerator::Field]
  def object_fields(defs, name)
    definition = defs.fetch(name)
    plain = fields(defs, definition, clearable: TypeGenerator::CLEARABLE.fetch(name, []))
    return plain unless variants(definition)

    union = flattened_union(defs, name)
    flattened = TypeGenerator::Field.new(
      attr: TypeGenerator::FLATTENED_UNION_ATTRS.fetch(name),
      flattened: true,
      required: true,
      nullable: false,
      type: TypeGenerator::Type.new(rbs: "#{union}::t", from: [:call, "#{union}.from_h"], to: [:send, 'to_h'])
    )
    [*plain, flattened]
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs name: String
  # @rbs return: Array[TypeGenerator::file]
  def object_files(defs, name)
    definition = defs.fetch(name)
    class_file = TypeGenerator::Emit.class_file(defs, defs.const(name), object_fields(defs, name))
    return [class_file] unless variants(definition)

    [class_file, *TypeGenerator::Unions.union_files(defs, flattened_union(defs, name), definition)]
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs name: String
  # @rbs return: String?
  def union_const(defs, name)
    definition = defs.fetch(name)
    case kind(definition)
    when :union then defs.const(name)
    when :object then flattened_union(defs, name) if variants(definition)
    end
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs name: String
  # @rbs return: String
  def flattened_union(defs, name)
    "#{defs.nested_const(name)}::#{TypeGenerator::Plan.camel(TypeGenerator::FLATTENED_UNION_ATTRS.fetch(name))}"
  end
end
