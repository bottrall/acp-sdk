# frozen_string_literal: true

# Emits the union, array-union, and enum strategies: discriminator tagging,
# the variant classes, and the dispatch bodies that route from_h/from_a.
module TypeGenerator::Unions
  extend self

  def discriminator(options)
    options.flat_map { |option| option.fetch('properties', {}).select { |_, schema| schema.key?('const') }.keys }
           .uniq
           .then { |keys| keys.size > 1 ? raise("Ambiguous discriminator: #{keys}") : keys.first }
  end

  def union_files(defs, union, definition)
    tag, tagged, untagged = variant_consts(defs, union, definition)
    tagged_classes = tagged.map do |option, variant|
      value = option.dig('properties', tag, 'const')
      TypeGenerator::Emit.class_file(defs, variant, variant_fields(defs, option, tag), tag: [tag, value])
    end
    untagged_classes = untagged.filter_map do |option, variant|
      next unless variant.start_with?("#{union}::")

      TypeGenerator::Emit.class_file(defs, variant, variant_fields(defs, option, tag))
    end
    dispatch = TypeGenerator::Dispatch.new(
      tag:,
      tagged: tagged.map { |option, variant| [option.dig('properties', tag, 'const'), variant] },
      untagged: untagged.map(&:last).zip(unique_keys(untagged.map { |option, _| required_keys(defs, option) }))
    )
    [union_file(defs, union, dispatch), *tagged_classes, *untagged_classes]
  end

  # The discriminator tag plus the variant constants union_files emits, paired
  # with their option and partitioned by the tag: tagged options name
  # themselves after the discriminator value (falling back to the allOf ref
  # when that would shadow a core class), untagged ones after their title —
  # or, when the option is just the refed def, the def's own constant.
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
  def subsumes_ref?(option) = option.key?('properties') && !option.key?('not') && variant_ref(option)

  # The defs a union's variant classes subsume, as [refed_def, variant_const]
  # pairs — the same constants union_files emits for those options.
  def variant_refs(defs, union, definition)
    _, tagged, untagged = variant_consts(defs, union, definition)
    [*tagged, *untagged].filter_map do |option, variant|
      [variant_ref(option), variant] if subsumes_ref?(option)
    end
  end

  def variant_names(options, tag)
    names = options.map { |option| TypeGenerator::Plan.camel(option.dig('properties', tag, 'const')) }
    return names unless names.intersect?(TypeGenerator::CORE_CLASSES)

    options.map { |option| variant_ref(option) }
  end

  def variant_ref(option) = option['allOf']&.first&.then { |schema| TypeGenerator::Plan.ref_name(schema.fetch('$ref')) }

  def variant_fields(defs, option, tag)
    inline = TypeGenerator::Resolve.fields(defs, option, except: [tag].compact)
    ref = variant_ref(option)
    ref ? inline + TypeGenerator::Resolve.object_fields(defs, ref) : inline
  end

  def untagged_const(defs, union, option)
    ref = variant_ref(option)
    return defs.const(ref) if ref && !option.key?('properties') &&
                              TypeGenerator::Resolve.kind(defs.fetch(ref)) == :object

    "#{union}::#{TypeGenerator::Plan.camel(option.fetch('title'))}"
  end

  def required_keys(defs, option)
    ref = variant_ref(option)
    option.fetch('required', []) + (ref ? defs.fetch(ref).fetch('required', []) : [])
  end

  def unique_keys(key_sets)
    key_sets.each_with_index.map do |keys, index|
      others = key_sets.reject.with_index { |_, other| other == index }.flatten
      (keys - others).first or raise "No distinguishing key among #{key_sets}"
    end
  end

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

  def type_alias(types)
    ['# @rbs!', "#   type t = #{types.first}", *types.drop(1).map { |type| "#          | #{type}" }]
  end

  def dispatch_body(dispatch)
    unless dispatch.tag
      branches = dispatch.untagged.map { |variant, key| ["hash.key?('#{key}')", ["#{variant}.from_h(hash)"]] }
      return key_dispatch(branches, 'hash')
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

  def enum_file(defs, const, definition)
    constants = TypeGenerator::Resolve.variants(definition).select { |option| option.key?('const') }.map do |option|
      value = option.fetch('const')
      name = (value.is_a?(String) ? value : option.fetch('title')).upcase.gsub(/[^A-Z\d]+/, '_')
      "#{name} = #{value.is_a?(String) ? "'#{value}'" : value}"
    end
    [TypeGenerator::Plan.path(const), TypeGenerator::Emit.source("module #{const}", [constants], defs.header)]
  end
end
