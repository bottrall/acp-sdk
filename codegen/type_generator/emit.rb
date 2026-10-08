# frozen_string_literal: true

# Renders Type and Field POROs as Ruby source text: the class file layout and
# the initialize/from_h/to_h bodies with their wrapped guard calls.
module TypeGenerator::Emit
  extend self

  def class_file(defs, const, fields, tag: nil)
    sections = [
      *fields.map { |field| attr_reader(field) },
      initialize_method(fields),
      from_h_method(const, fields),
      to_h_method(fields, tag)
    ]
    [TypeGenerator::Plan.path(const), source("class #{const}", sections, defs.header)]
  end

  def source(opening, sections, header)
    body = sections.map { |lines| indent(lines, 2).join("\n") }.join("\n\n")
    "#{header}\n#{opening}\n#{body}\nend\n"
  end

  def indent(lines, depth) = lines.map { |line| "#{' ' * depth}#{line}" }

  def rbs_type(field)
    return field.type.rbs unless field.nilable?

    field.clearable? ? "#{optional(field.type.rbs)} | :unset" : optional(field.type.rbs)
  end

  def attr_reader(field)
    ["# @dynamic #{field.attr}", "attr_reader :#{field.attr} #: #{rbs_type(field)}"]
  end

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
  def from_h_method(const, fields)
    param = fields.empty? ? '_hash' : 'hash'
    expressions = fields.to_h { |field| [field, from_expression(field)] }
    blocky, _plain = fields.partition { |field| piece_block(expressions.fetch(field)) }
    args = fields.map do |field|
      expression = expressions.fetch(field)
      [field.attr, piece_block(expression) ? nil : expression]
    end
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

  def new_call(args, column)
    return ['new'] if args.empty?

    single = "new(#{args.map { |name, expr| new_arg(name, expr) }.join(', ')})"
    return [single] if column + single.length <= TypeGenerator::MAX_LINE_LENGTH

    lines = args.each_with_index.flat_map do |(name, expr), index|
      comma = index == args.size - 1 ? '' : ','
      if expr.nil?
        indent(["#{name}:"], 2).tap { |arg_lines| arg_lines[-1] += comma }
      else
        indent(render(expr, column + 2, "#{name}: ", comma), 2)
      end
    end
    ['new(', *lines, ')']
  end

  def new_arg(name, expr)
    expr.nil? ? "#{name}:" : "#{name}: #{inline(expr)}"
  end

  def arg_comma(size, index)
    index == size - 1 ? '' : ','
  end

  def from_expression(field)
    return convert(field.type.from, 'hash', false) if field.flattened?

    source =
      if field.required?
        ["#{TypeGenerator::CHECK}.key", ['hash', "'#{field.json}'"], nil, nil]
      elsif field.clearable?
        "hash.fetch('#{field.json}', :unset)"
      else
        "hash['#{field.json}']"
      end
    unless field.type.check
      return convert(field.type.from, source.is_a?(String) ? source : inline(source), field.nilable?)
    end

    guard(field.type.check, source, "'#{field.json}'", field.nilable?, field.clearable?)
  end

  # Builds the guard call for a resolved type as a piece: [callee, args,
  # block, cast]. Top-level guards take the field path as a string; guards
  # nested in a container take the block's `path` parameter, so the Check
  # module can report absolute paths.
  def guard(spec, source, path, nilable, clearable)
    check = TypeGenerator::CHECK
    opts = guard_options(nilable, clearable)
    case spec
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

  def guard_options(nilable, clearable)
    { allow_nil: nilable, allow_unset: clearable }.select { |_, set| set }.map { |name, _| "#{name}: true" }
  end

  def bounds(min, max)
    { min: min, max: max }.select { |_, value| value }.map { |name, value| "#{name}: #{numeric(value)}" }
  end

  def numeric(value) = value.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1_').reverse

  def enum_values(values)
    words = values.all?(String) && values.size > 1 && values.all? { |value| value.match?(/\A[\w-]+\z/) }
    return "%w[#{values.join(' ')}]" if words

    "[#{values.map { |value| enum_value(value) }.join(', ')}]"
  end

  def enum_value(value)
    return numeric(value) if value.is_a?(Integer)

    "'#{value.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'")}'"
  end

  def inline(piece)
    return piece if piece.is_a?(String)

    callee, args, block, cast = piece
    rendered = "#{callee}(#{args.map { |arg| inline(arg) }.join(', ')})"
    rendered += " { |#{block[0]}| #{inline(block[1])} }" if block
    rendered += " #{cast}" if cast
    rendered
  end

  def piece_block(piece) = piece.is_a?(Array) ? piece[2] : nil

  # Renders a piece or plain expression as one or more lines. `column` is the
  # final column the first line starts at, `suffix` (e.g. an argument comma)
  # closes the last line; nested lines indent by two.
  def render(piece, column, prefix = '', suffix = '')
    line = "#{prefix}#{inline(piece)}#{suffix}"
    return [line] if column + line.length <= TypeGenerator::MAX_LINE_LENGTH || piece.is_a?(String)

    callee, args, block, cast = piece
    tail = cast ? " #{cast}" : ''
    rendered_args = args.map { |arg| inline(arg) }.join(', ')
    head = args.empty? ? "#{prefix}#{callee}" : "#{prefix}#{callee}(#{rendered_args})"
    if block && column + "#{head} do |#{block[0]}|".length <= TypeGenerator::MAX_LINE_LENGTH
      return ["#{head} do |#{block[0]}|", *indent(render(block[1], column + 2), 2), "end#{tail}#{suffix}"]
    end

    lines = args.each_with_index.flat_map do |arg, index|
      indent(render(arg, column + 2, '', arg_comma(args.size, index)), 2)
    end
    return ["#{prefix}#{callee}(", *lines, ")#{tail}#{suffix}"] unless block

    body = indent(render(block[1], column + 2), 2)
    ["#{prefix}#{callee}(", *lines, ") do |#{block[0]}|", *body, "end#{tail}#{suffix}"]
  end

  def to_h_method(fields, tag)
    entry = ->(field) { "'#{field.json}' => #{convert(field.type.to, field.attr, field.nilable?)}" }
    flattened, plain = fields.partition(&:flattened?)
    clearable, settled = plain.partition(&:clearable?)
    required, optional = settled.partition(&:required?)
    nullable, present = required.partition(&:nullable?)
    entries = [*(tag && "'#{tag[0]}' => '#{tag[1]}'"), *(optional.empty? ? required : present + optional).map(&entry)]
    suffix = [
      ('.compact' unless optional.empty?),
      (".merge(#{nullable.map(&entry).join(', ')})" unless optional.empty? || nullable.empty?),
      (".merge({ #{clearable.map(&entry).join(', ')} }.reject { |_, value| value == :unset })" unless clearable.empty?),
      *flattened.map { |field| ".merge(#{field.attr}.to_h)" }
    ].join
    ["# @rbs return: #{TypeGenerator::RAW_HASH}", 'def to_h', *indent(hash_literal(entries, suffix, 4), 2), 'end']
  end

  def call(prefix, args, column)
    return [prefix] if args.empty?

    single = "#{prefix}(#{args.join(', ')})"
    return [single] if column + single.length <= TypeGenerator::MAX_LINE_LENGTH

    lines = args.each_with_index.map do |arg, index|
      "#{arg}#{',' unless index == args.size - 1}"
    end
    ["#{prefix}(", *indent(lines, 2), ')']
  end

  def hash_literal(entries, suffix, column)
    single = entries.empty? ? "{}#{suffix}" : "{ #{entries.join(', ')} }#{suffix}"
    return [single] if column + single.length <= TypeGenerator::MAX_LINE_LENGTH

    ['{', *entries.map { |entry| "  #{entry}," }.tap { |lines| lines[-1] = lines[-1].chomp(',') }, "}#{suffix}"]
  end

  # Conversions stay tagged arrays rather than POROs: they only exist to be pattern-matched here, and array patterns
  # match the nested shapes (`[:map, [:send, 'to_h']]`) directly.
  def convert(conversion, expression, nilable)
    dot = nilable ? '&.' : '.'
    case conversion
    in nil then expression
    in [:call, callee] if nilable then "#{expression}&.then { |value| #{callee}(value) }"
    in [:call, callee] then "#{callee}(#{expression})"
    in [:send, method] then "#{expression}#{dot}#{method}"
    in [:map | :transform_values => method, [:send, inner]] then "#{expression}#{dot}#{method}(&:#{inner})"
    in [:map | :transform_values => method, inner]
      "#{expression}#{dot}#{method} { |item| #{convert(inner, 'item', false)} }"
    end
  end

  def optional(rbs)
    return rbs if rbs == 'untyped' || rbs.split(' | ').include?('nil')

    rbs.include?('|') ? "(#{rbs})?" : "#{rbs}?"
  end
end
