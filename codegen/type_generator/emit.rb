# frozen_string_literal: true

module TypeGenerator::Emit
  extend self

  # @rbs defs: TypeGenerator::Schema
  # @rbs const: String
  # @rbs fields: Array[TypeGenerator::Field]
  # @rbs tag: [String, String]?
  # @rbs return: TypeGenerator::file
  def class_file(defs, const, fields, tag: nil)
    sections = [
      *fields.map { |field| attr_reader(field) },
      initialize_method(fields),
      from_h_method(const, fields),
      to_h_method(fields, tag)
    ]
    [TypeGenerator::Naming.path(const), source("class #{const}", sections, defs.header)]
  end

  # @rbs opening: String
  # @rbs sections: Array[Array[String]]
  # @rbs header: String
  # @rbs return: String
  def source(opening, sections, header)
    body = sections.map { |lines| indent(lines, 2).join("\n") }.join("\n\n")
    "#{header}\n#{opening}\n#{body}\nend\n"
  end

  # @rbs lines: Array[String]
  # @rbs depth: Integer
  # @rbs return: Array[String]
  def indent(lines, depth) = lines.map { |line| "#{' ' * depth}#{line}" }

  # @rbs field: TypeGenerator::Field
  # @rbs return: String
  def rbs_type(field)
    return field.type.rbs unless field.nilable?

    field.clearable? ? "#{optional(field.type.rbs)} | :unset" : optional(field.type.rbs)
  end

  # @rbs field: TypeGenerator::Field
  # @rbs return: Array[String]
  def attr_reader(field)
    ["# @dynamic #{field.attr}", "attr_reader :#{field.attr} #: #{rbs_type(field)}"]
  end

  # @rbs fields: Array[TypeGenerator::Field]
  # @rbs return: Array[String]
  def initialize_method(fields)
    required, optional = fields.partition(&:required?)
    defaults = optional.map { |field| "#{field.attr}: #{field.clearable? ? ':unset' : 'nil'}" }
    params = [*required.map { |field| "#{field.attr}:" }, *defaults]
    [
      *fields.map { |field| "# @rbs #{field.attr}: #{rbs_type(field)}" },
      '# @rbs return: void',
      *call('def initialize', params, 2),
      *fields.map { |field| "  @#{field.attr} = #{field.attr}" },
      '  freeze',
      'end'
    ]
  end

  # A do...end in a keyword-argument position binds its block to `new`, so
  # fields whose guard takes a block are assigned to locals first.
  #
  # @rbs const: String
  # @rbs fields: Array[TypeGenerator::Field]
  # @rbs return: Array[String]
  def from_h_method(const, fields)
    param = fields.empty? ? '_hash' : 'hash'
    expressions = fields.to_h { |field| [field, from_expression(field)] }
    blocky = fields.select { |field| piece_block(expressions.fetch(field)) }
    args = fields.map do |field|
      expression = expressions.fetch(field)
      [field.attr, piece_block(expression) ? nil : expression]
    end #: Array[[String, TypeGenerator::expression?]]
    temps = blocky.map { |field| render(expressions.fetch(field), 4, "#{field.attr} = ") }
    [
      "# @rbs #{param}: #{TypeGenerator::RAW_HASH}",
      "# @rbs return: #{const}",
      "def self.from_h(#{param})",
      *temps.flat_map { |lines| indent(lines, 2) },
      *indent(new_call(args, 4), 2),
      'end'
    ]
  end

  # @rbs args: Array[[String, TypeGenerator::expression?]]
  # @rbs column: Integer
  # @rbs return: Array[String]
  def new_call(args, column)
    return ['new'] if args.empty?

    single = "new(#{args.map { |name, expr| new_arg(name, expr) }.join(', ')})"
    wrap(single, column, 'new(', ')') do
      commas(args).map do |(name, expr), comma|
        expr.nil? ? ["#{name}:#{comma}"] : render(expr, column + 2, "#{name}: ", comma)
      end
    end
  end

  # @rbs name: String
  # @rbs expr: TypeGenerator::expression?
  # @rbs return: String
  def new_arg(name, expr)
    expr.nil? ? "#{name}:" : "#{name}: #{inline(expr)}"
  end

  # @rbs single: String
  # @rbs column: Integer
  # @rbs opening: String
  # @rbs closing: String
  # @rbs &items: () -> Array[Array[String]]
  # @rbs return: Array[String]
  def wrap(single, column, opening, closing)
    return [single] if fits?(single, column)

    [opening, *yield.flat_map { |lines| indent(lines, 2) }, closing]
  end

  # @rbs line: String
  # @rbs column: Integer
  # @rbs return: bool
  def fits?(line, column) = column + line.length <= TypeGenerator::MAX_LINE_LENGTH

  # @rbs items: Array[untyped]
  # @rbs return: Array[[untyped, String]]
  def commas(items) = items.each_with_index.map { |item, index| [item, index == items.size - 1 ? '' : ','] }

  # @rbs field: TypeGenerator::Field
  # @rbs return: TypeGenerator::expression
  def from_expression(field)
    return convert(field.type.from, 'hash', false) if field.flattened?

    source =
      if field.required?
        ["#{TypeGenerator::CHECK}.key", ['hash', "'#{field.json}'"], nil, nil]
      elsif field.clearable?
        "hash.fetch('#{field.json}', :unset)"
      else
        "hash['#{field.json}']"
      end #: TypeGenerator::expression
    unless field.type.check
      return convert(field.type.from, source.is_a?(String) ? source : inline(source), field.nilable?)
    end

    guard(field.type.check, source, "'#{field.json}'", field.nilable?, field.clearable?)
  end

  # Top-level guards take the field path as a string; guards nested in a
  # container take the block's `path` parameter, so the Check module can report
  # absolute paths.
  #
  # @rbs spec: TypeGenerator::check
  # @rbs source: TypeGenerator::expression
  # @rbs path: String
  # @rbs nilable: bool
  # @rbs clearable: bool
  # @rbs return: TypeGenerator::piece
  def guard(spec, source, path, nilable, clearable)
    check = TypeGenerator::CHECK
    opts = guard_options(nilable, clearable)
    # Steep 2.1 rejects pattern matching as unsupported syntax and leaves this
    # case unchecked.
    case spec # steep:ignore UnsupportedSyntax
    in [:string] then ["#{check}.string", [source, path, *opts], nil, nil]
    in [:boolean] then ["#{check}.boolean", [source, path, *opts], nil, nil]
    in [:integer, min, max] then ["#{check}.integer", [source, path, *bounds(min, max), *opts], nil, nil]
    in [:number, min, max] then ["#{check}.number", [source, path, *bounds(min, max), *opts], nil, nil]
    in [:enum, values] then ["#{check}.enum", [source, path, enum_values(values), *opts], nil, nil]
    in [:one_of, classes, items]
      block = items ? ['item, path', guard(items, 'item', 'path', false, false)] : nil
      ["#{check}.one_of", [source, path, "[#{classes.join(', ')}]", *opts], block, nil]
    in [:hash, value]
      ["#{check}.hash", [source, path, *opts], ['value, path', guard(value, 'value', 'path', false, false)], nil]
    in [:array, item]
      ["#{check}.array", [source, path, *opts], ['item, path', guard(item, 'item', 'path', false, false)], nil]
    in [:object, const] then ["#{check}.object", [source, path, const, *opts], nil, nil]
    in [:objects, const] then ["#{check}.objects", [source, path, const, *opts], nil, nil]
    end
  end

  # @rbs nilable: bool
  # @rbs clearable: bool
  # @rbs return: Array[String]
  def guard_options(nilable, clearable)
    { allow_nil: nilable, allow_unset: clearable }.select { |_, set| set }.map { |name, _| "#{name}: true" }
  end

  # @rbs min: Numeric?
  # @rbs max: Numeric?
  # @rbs return: Array[String]
  def bounds(min, max)
    { min: min, max: max }.filter_map { |name, value| "#{name}: #{numeric(value)}" if value }
  end

  # @rbs value: Numeric
  # @rbs return: String
  def numeric(value) = value.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1_').reverse

  # @rbs values: Array[String | Integer]
  # @rbs return: String
  def enum_values(values)
    words = values.size > 1 && values.all? { |value| value.is_a?(String) && value.match?(/\A[\w-]+\z/) }
    return "%w[#{values.join(' ')}]" if words

    "[#{values.map { |value| enum_value(value) }.join(', ')}]"
  end

  # @rbs value: String | Integer
  # @rbs return: String
  def enum_value(value)
    return numeric(value) if value.is_a?(Integer)

    "'#{value.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'")}'"
  end

  # @rbs piece: TypeGenerator::expression
  # @rbs return: String
  def inline(piece)
    return piece if piece.is_a?(String)

    callee, args, block, cast = piece
    rendered = "#{callee}(#{args.map { |arg| inline(arg) }.join(', ')})"
    rendered += " { |#{block[0]}| #{inline(block[1])} }" if block
    rendered += " #{cast}" if cast
    rendered
  end

  # @rbs piece: TypeGenerator::expression
  # @rbs return: [String, TypeGenerator::expression]?
  def piece_block(piece) = piece.is_a?(Array) ? piece[2] : nil

  # @rbs piece: TypeGenerator::expression
  # @rbs column: Integer
  # @rbs prefix: String
  # @rbs suffix: String
  # @rbs return: Array[String]
  def render(piece, column, prefix = '', suffix = '')
    line = "#{prefix}#{inline(piece)}#{suffix}"
    return [line] if fits?(line, column) || piece.is_a?(String)

    callee, args, block, cast = piece
    tail = cast ? " #{cast}" : ''
    rendered_args = args.map { |arg| inline(arg) }.join(', ')
    head = args.empty? ? "#{prefix}#{callee}" : "#{prefix}#{callee}(#{rendered_args})"
    if block && fits?("#{head} do |#{block[0]}|", column)
      return ["#{head} do |#{block[0]}|", *indent(render(block[1], column + 2), 2), "end#{tail}#{suffix}"]
    end

    lines = commas(args).flat_map { |arg, comma| indent(render(arg, column + 2, '', comma), 2) }
    return ["#{prefix}#{callee}(", *lines, ")#{tail}#{suffix}"] unless block

    body = indent(render(block[1], column + 2), 2)
    ["#{prefix}#{callee}(", *lines, ") do |#{block[0]}|", *body, "end#{tail}#{suffix}"]
  end

  # @rbs fields: Array[TypeGenerator::Field]
  # @rbs tag: [String, String]?
  # @rbs return: Array[String]
  def to_h_method(fields, tag)
    entry = ->(field) { "'#{field.json}' => #{to_expression(field)}" }
    flattened, plain = fields.partition(&:flattened?)
    clearable, settled = plain.partition(&:clearable?)
    required, optional = settled.partition(&:required?)
    nullable, present = required.partition(&:nullable?)
    entries = [
      tag && "'#{tag[0]}' => '#{tag[1]}'",
      *(optional.empty? ? required : present + optional).map(&entry)
    ].compact
    suffix = [
      ('.compact' unless optional.empty?),
      (".merge(#{nullable.map(&entry).join(', ')})" unless optional.empty? || nullable.empty?),
      (".merge({ #{clearable.map(&entry).join(', ')} }.reject { |_, value| value == :unset })" unless clearable.empty?),
      *flattened.map { |field| ".merge(#{field.attr}.to_h)" }
    ].join
    ["# @rbs return: #{TypeGenerator::RAW_HASH}", 'def to_h', *indent(hash_literal(entries, suffix, 4), 2), 'end']
  end

  # The sentinel is told apart by class because Steep narrows the union on `is_a?` but not on `== :unset`.
  #
  # @rbs field: TypeGenerator::Field
  # @rbs return: String
  def to_expression(field)
    converted = convert(field.type.to, field.attr, field.nilable?)
    return converted unless field.clearable? && field.type.to

    "#{field.attr}.is_a?(Symbol) ? #{field.attr} : #{converted}"
  end

  # @rbs prefix: String
  # @rbs args: Array[String]
  # @rbs column: Integer
  # @rbs return: Array[String]
  def call(prefix, args, column)
    return [prefix] if args.empty?

    wrap("#{prefix}(#{args.join(', ')})", column, "#{prefix}(", ')') do
      commas(args).map { |arg, comma| ["#{arg}#{comma}"] }
    end
  end

  # @rbs entries: Array[String]
  # @rbs suffix: String
  # @rbs column: Integer
  # @rbs return: Array[String]
  def hash_literal(entries, suffix, column)
    return ["{}#{suffix}"] if entries.empty?

    wrap("{ #{entries.join(', ')} }#{suffix}", column, '{', "}#{suffix}") do
      commas(entries).map { |entry, comma| ["#{entry}#{comma}"] }
    end
  end

  # Conversions stay tagged arrays rather than POROs: they only exist to be pattern-matched here, and array patterns
  # match the nested shapes (`[:map, [:send, 'to_h']]`) directly.
  #
  # @rbs conversion: TypeGenerator::conversion?
  # @rbs expression: String
  # @rbs nilable: bool
  # @rbs return: String
  def convert(conversion, expression, nilable)
    dot = nilable ? '&.' : '.'
    # Steep 2.1 rejects pattern matching as unsupported syntax and leaves this
    # case unchecked.
    case conversion # steep:ignore UnsupportedSyntax
    in nil then expression
    in [:call, callee] if nilable then "#{expression}&.then { |value| #{callee}(value) }"
    in [:call, callee] then "#{callee}(#{expression})"
    in [:send, method] then "#{expression}#{dot}#{method}"
    in [:map | :transform_values => method, [:send, inner]] then "#{expression}#{dot}#{method}(&:#{inner})"
    in [:map | :transform_values => method, inner]
      "#{expression}#{dot}#{method} { |item| #{convert(inner, 'item', false)} }"
    end
  end

  # @rbs rbs: String
  # @rbs return: String
  def optional(rbs)
    return rbs if rbs == 'untyped' || rbs.split(' | ').include?('nil')

    rbs.include?('|') ? "(#{rbs})?" : "#{rbs}?"
  end
end
