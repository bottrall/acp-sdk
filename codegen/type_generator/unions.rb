# frozen_string_literal: true

module TypeGenerator::Unions
  extend self

  # @rbs options: Array[Hash[String, untyped]]
  # @rbs return: String?
  def discriminator(options)
    options.flat_map { |option| (option['properties'] || {}).select { |_, schema| schema.key?('const') }.keys }
           .uniq
           .then { |keys| keys.size > 1 ? raise("Ambiguous discriminator: #{keys}") : keys.first }
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs union: String
  # @rbs definition: Hash[String, untyped]
  # @rbs return: Array[TypeGenerator::file]
  def union_files(defs, union, definition)
    tag, tagged, untagged = variant_consts(defs, union, definition)
    tagged_classes = tagged.map do |option, variant|
      value = option.dig('properties', tag, 'const')
      TypeGenerator::Emit.class_file(defs, variant, variant_fields(defs, option, tag), tag: tag && [tag, value])
    end
    untagged_classes = untagged.filter_map do |option, variant|
      next unless variant.start_with?("#{union}::")

      TypeGenerator::Emit.class_file(defs, variant, variant_fields(defs, option, tag))
    end
    keys = unique_keys(untagged.map { |option, _| required_keys(defs, option) })
    # zip can't see that both arrays have one entry per untagged variant, so it
    # types each key as nilable.
    untagged_keys = untagged.map(&:last).zip(keys) #: Array[[String, String]]
    dispatch = TypeGenerator::Dispatch.new(
      tag:,
      tagged: tagged.map { |option, variant| [option.dig('properties', tag, 'const'), variant] },
      untagged: untagged_keys
    )
    [union_file(defs, union, dispatch), *tagged_classes, *untagged_classes]
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs union: String
  # @rbs definition: Hash[String, untyped]
  # @rbs return: [String?, Array[[Hash[String, untyped], String]], Array[[Hash[String, untyped], String]]]
  def variant_consts(defs, union, definition)
    options = TypeGenerator::Resolve.variants(definition).reject { |option| option.key?('not') }
    tag = discriminator(options)
    tagged, untagged = options.partition { |option| tag && option.dig('properties', tag, 'const') }
    tagged_pairs = tagged.zip(variant_names(tagged, tag)).map { |option, name| [option, "#{union}::#{name}"] }
    untagged_pairs = untagged.map { |option| [option, untagged_const(defs, union, option)] }
    [tag, tagged_pairs, untagged_pairs]
  end

  # A def reached only through an option like this is subsumed by the variant
  # class: the option carries its own properties, which inline the refed def's
  # fields, so no flat class is emitted for it. `not` options never become
  # variants, so their refs stay normal edges.
  #
  # @rbs option: Hash[String, untyped]
  # @rbs return: boolish
  def subsumes_ref?(option) = option.key?('properties') && !option.key?('not') && variant_ref(option)

  # @rbs defs: TypeGenerator::Schema
  # @rbs union: String
  # @rbs definition: Hash[String, untyped]
  # @rbs return: Array[[String, String]]
  def variant_refs(defs, union, definition)
    _, tagged, untagged = variant_consts(defs, union, definition)
    [*tagged, *untagged].filter_map do |option, variant|
      ref = variant_ref(option)
      [ref, variant] if ref && subsumes_ref?(option)
    end
  end

  # @rbs options: Array[Hash[String, untyped]]
  # @rbs tag: String?
  # @rbs return: Array[String?]
  def variant_names(options, tag)
    names = options.map { |option| TypeGenerator::Plan.camel(option.dig('properties', tag, 'const')) }
    return names unless names.intersect?(TypeGenerator::CORE_CLASSES)

    options.map { |option| variant_ref(option) }
  end

  # @rbs option: Hash[String, untyped]
  # @rbs return: String?
  def variant_ref(option) = option['allOf']&.first&.then { |schema| TypeGenerator::Plan.ref_name(schema.fetch('$ref')) }

  # @rbs defs: TypeGenerator::Schema
  # @rbs option: Hash[String, untyped]
  # @rbs tag: String?
  # @rbs return: Array[TypeGenerator::Field]
  def variant_fields(defs, option, tag)
    inline = TypeGenerator::Resolve.fields(defs, option, except: [tag].compact)
    ref = variant_ref(option)
    ref ? inline + TypeGenerator::Resolve.object_fields(defs, ref) : inline
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs union: String
  # @rbs option: Hash[String, untyped]
  # @rbs return: String
  def untagged_const(defs, union, option)
    ref = variant_ref(option)
    return defs.const(ref) if ref && !option.key?('properties') &&
                              TypeGenerator::Resolve.kind(defs.fetch(ref)) == :object

    "#{union}::#{TypeGenerator::Plan.camel(option.fetch('title'))}"
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs option: Hash[String, untyped]
  # @rbs return: Array[String]
  def required_keys(defs, option)
    ref = variant_ref(option)
    own = option.fetch('required', [])
    ref ? own + defs.fetch(ref).fetch('required', []) : own
  end

  # @rbs key_sets: Array[Array[String]]
  # @rbs return: Array[String]
  def unique_keys(key_sets)
    key_sets.each_with_index.map do |keys, index|
      others = key_sets.reject.with_index { |_, other| other == index }.flatten
      (keys - others).first or raise "No distinguishing key among #{key_sets}"
    end
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs union: String
  # @rbs dispatch: TypeGenerator::Dispatch
  # @rbs return: TypeGenerator::file
  def union_file(defs, union, dispatch)
    variants = [*dispatch.tagged.map(&:last), *dispatch.untagged.map(&:first), TypeGenerator::RAW_HASH]
    from_h = [
      "# @rbs hash: #{TypeGenerator::RAW_HASH}",
      '# @rbs return: t',
      'def self.from_h(hash)',
      *TypeGenerator::Emit.indent(dispatch_body(dispatch), 2),
      'end'
    ]
    [
      TypeGenerator::Plan.path(union),
      TypeGenerator::Emit.source("module #{union}", [type_alias(variants), from_h], defs.header)
    ]
  end

  # @rbs types: Array[String]
  # @rbs return: Array[String]
  def type_alias(types)
    ['# @rbs!', "#   type t = #{types.first}", *types.drop(1).map { |type| "#          | #{type}" }]
  end

  # @rbs dispatch: TypeGenerator::Dispatch
  # @rbs return: Array[String]
  def dispatch_body(dispatch)
    unless dispatch.tag
      return key_dispatch(
        dispatch.untagged.map { |variant, key| ["hash.key?('#{key}')", ["#{variant}.from_h(hash)"]] },
        'hash'
      )
    end

    raise "Several untagged variants alongside #{dispatch.tag}" if dispatch.untagged.size > 1

    [
      "case hash['#{dispatch.tag}']",
      *dispatch.tagged.map { |value, variant| "when '#{value}' then #{variant}.from_h(hash)" },
      *dispatch.untagged.map { |variant, _| "when nil then #{variant}.from_h(hash)" },
      'else hash',
      'end'
    ]
  end

  # @rbs branches: Array[[String, Array[String]]]
  # @rbs fallback: String
  # @rbs return: Array[String]
  def key_dispatch(branches, fallback)
    [
      *branches.each_with_index.flat_map do |(condition, result), index|
        ["#{index.zero? ? 'if' : 'elsif'} #{condition}", *TypeGenerator::Emit.indent(result, 2)]
      end,
      'else',
      "  #{fallback}",
      'end'
    ]
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs union: String
  # @rbs definition: Hash[String, untyped]
  # @rbs return: TypeGenerator::file
  def array_union_file(defs, union, definition)
    items = TypeGenerator::Resolve.variants(definition)
                                  .map { |option| TypeGenerator::Plan.ref_name(option.fetch('items').fetch('$ref')) }
    keys = unique_keys(items.map { |name| defs.fetch(name).fetch('required', []) })
    branches = items.zip(keys).map do |name, key|
      [
        "items.all? { |item| item.key?('#{key}') }",
        # The index segment makes a variant's parse failure report its position,
        # and the cast keeps Steep from checking the branch against the first
        # member of `t` only.
        TypeGenerator::Emit.render(
          ['items.each_with_index.map', [],
           ['item, index', ["#{TypeGenerator::CHECK}.object", ['item', '[index]', defs.const(name)], nil, nil]],
           "#: Array[#{defs.const(name)}]"],
          6
        )
      ]
    end
    from_a = [
      "# @rbs items: Array[#{TypeGenerator::RAW_HASH}]",
      '# @rbs return: t',
      'def self.from_a(items)',
      *TypeGenerator::Emit.indent(key_dispatch(branches, 'items'), 2),
      'end'
    ]
    types = [*items.map { |name| "Array[#{defs.const(name)}]" }, "Array[#{TypeGenerator::RAW_HASH}]"]
    [
      TypeGenerator::Plan.path(union),
      TypeGenerator::Emit.source("module #{union}", [type_alias(types), from_a], defs.header)
    ]
  end

  # @rbs defs: TypeGenerator::Schema
  # @rbs const: String
  # @rbs definition: Hash[String, untyped]
  # @rbs return: TypeGenerator::file
  def enum_file(defs, const, definition)
    constants = TypeGenerator::Resolve.variants(definition).select { |option| option.key?('const') }.map do |option|
      value = option.fetch('const')
      name = (value.is_a?(String) ? value : option.fetch('title')).upcase.gsub(/[^A-Z\d]+/, '_')
      "#{name} = #{value.is_a?(String) ? "'#{value}'" : value}"
    end
    [TypeGenerator::Plan.path(const), TypeGenerator::Emit.source("module #{const}", [constants], defs.header)]
  end
end
