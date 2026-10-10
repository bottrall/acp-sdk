# frozen_string_literal: true

# Turns schema JSON into Type and Field POROs: classifies each def's kind and
# resolves property schemas to the conversions and guards from_h renders.
module TypeGenerator::Resolve
  extend self

  def variants(definition) = definition['oneOf'] || definition['anyOf']

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

  def object_like?(schema) = schema.key?('properties') || schema.key?('allOf') || schema['type'] == 'object'

  def definition_files(defs, name)
    return [] unless defs.generated?(name)

    definition = defs.fetch(name)
    case kind(definition)
    when :object then object_files(defs, name)
    when :union then TypeGenerator::Unions.union_files(defs, union_const(defs, name), definition)
    when :array_union then [TypeGenerator::Unions.array_union_file(defs, defs.const(name), definition)]
    when :enum then [TypeGenerator::Unions.enum_file(defs, defs.const(name), definition)]
    else []
    end
  end

  def resolve(defs, schema)
    if (ref = schema['$ref']) then resolve_ref(defs, TypeGenerator::Plan.ref_name(ref))
    elsif (options = schema['allOf'] || schema['anyOf'])
      resolve(defs, options.find { |option| option['type'] != 'null' })
    else
      resolve_inline(defs, schema)
    end
  end

  def resolve_inline(defs, schema)
    case Array(schema['type']) - ['null']
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

  def primitive_check(schema, type)
    case type
    when 'boolean' then [:boolean]
    when 'integer' then [:integer, schema['minimum'], schema['maximum']]
    when 'number' then [:number, schema['minimum'], schema['maximum']]
    else [:string]
    end
  end

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
      check = [:enum, options.map { |option| option.fetch('const') }] if options.all? { |option| option.key?('const') }
      TypeGenerator::Type.new(rbs:, check:)
    when :primitive_union
      options = variants(definition)
      types = options.map { |option| option['type'] == 'null' ? 'nil' : resolve(defs, option).rbs }
      non_null = options.reject { |option| option['type'] == 'null' }
      classes = non_null.flat_map { |option| TypeGenerator::RUBY_CLASSES.fetch(option.fetch('type'), %w[Array]) }
      # A typed-array variant's items are checked by one_of after the Array
      # class matches, so the spec passes the inner item check, not [:array, ...].
      items = non_null.filter_map { |option| resolve(defs, option).check[1] if option['type'] == 'array' }.first
      TypeGenerator::Type.new(rbs: types.join(' | '), nullable: types.include?('nil'), check: [:one_of, classes, items])
    else resolve(defs, definition)
    end
  end

  def elementwise(method, conversion) = conversion && [method, conversion]

  def fields(defs, schema, except: [], clearable: [])
    required = schema.fetch('required', [])
    schema.fetch('properties', {}).except(*except).map do |json, property|
      type = resolve(defs, property)
      # A property with no declared type accepts any JSON value, null included,
      # so its nil must survive the optional fields' compaction in to_h.
      untyped = TypeGenerator::TYPELESS_PROPERTY_KEYS.none? { |key| property.key?(key) }
      nullable = untyped || type.nullable? || Array(property['type']).include?('null') ||
                 Array(property['anyOf']).any? { |option| option['type'] == 'null' }
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

  def object_files(defs, name)
    definition = defs.fetch(name)
    class_file = TypeGenerator::Emit.class_file(defs, defs.const(name), object_fields(defs, name))
    return [class_file] unless variants(definition)

    [class_file, *TypeGenerator::Unions.union_files(defs, union_const(defs, name), definition)]
  end

  # The union constant a def's variants nest under — itself for a bare union,
  # flattened into the object for a schemars-flattened one; nil when the def
  # has no variants.
  def union_const(defs, name)
    definition = defs.fetch(name)
    case kind(definition)
    when :union then defs.const(name)
    when :object then flattened_union(defs, name) if variants(definition)
    end
  end

  def flattened_union(defs, name)
    "#{defs.nested_const(name)}::#{TypeGenerator::Plan.camel(TypeGenerator::FLATTENED_UNION_ATTRS.fetch(name))}"
  end
end
