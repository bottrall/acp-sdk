# frozen_string_literal: true

module SchemaDiff
  extend self

  # Upstream words its capability gates as "Agents MUST only send this update
  # when…", "MUST NOT send … unless…" or "SHOULD only send it when…".
  SEND_RULE = /\b(?:MUST|SHOULD)\b.*\b(?:only|unless|until)\b|\b[Oo]nly send\b/

  Edition = Data.define(
    :schema, #: Hash[String, untyped]
    :meta #: Hash[String, untyped]
  )

  Release = Data.define(
    :version, #: String
    :stable, #: SchemaDiff::Edition
    :unstable #: SchemaDiff::Edition
  )

  Category = Data.define(
    :title, #: String
    :items #: Array[String]
  )

  # @rbs before: SchemaDiff::Release
  # @rbs after: SchemaDiff::Release
  # @rbs return: String
  def markdown(before, after)
    stable = changes(before.stable, after.stable)
    stable_items = stable.to_h { |category| [category.title, category.items] }
    # The unstable schema extends the stable one, so its section leaves out what
    # the stable section already lists.
    unstable = changes(before.unstable, after.unstable).map do |category|
      category.with(items: category.items - stable_items.fetch(category.title))
    end
    [
      "## ACP schema diff: #{before.version} → #{after.version}",
      section('Stable (`schema.json`, `meta.json`)', stable),
      section('Unstable, beyond stable (`schema.unstable.json`, `meta.unstable.json`)', unstable)
    ].join("\n\n")
  end

  # @rbs before: SchemaDiff::Edition
  # @rbs after: SchemaDiff::Edition
  # @rbs return: Array[SchemaDiff::Category]
  def changes(before, after)
    methods_before = method_names(before.meta)
    methods_after = method_names(after.meta)
    defs_before = before.schema.fetch('$defs')
    defs_after = after.schema.fetch('$defs')
    changed = (defs_before.keys & defs_after.keys).reject { |name| defs_before[name] == defs_after[name] }
    [
      Category.new(title: 'Methods added', items: methods_after - methods_before),
      Category.new(title: 'Methods removed', items: methods_before - methods_after),
      Category.new(title: 'Defs added', items: code(defs_after.keys - defs_before.keys)),
      Category.new(title: 'Defs removed', items: code(defs_before.keys - defs_after.keys)),
      Category.new(title: 'Defs changed', items: code(changed)),
      Category.new(title: 'New send rules', items: send_rules(after.schema) - send_rules(before.schema))
    ]
  end

  # @rbs meta: Hash[String, untyped]
  # @rbs return: Array[String]
  def method_names(meta)
    meta.select { |_, methods| methods.is_a?(Hash) }.flat_map do |section, methods|
      methods.values.map { |method| "`#{method}` (#{section})" }
    end
  end

  # @rbs schema: Hash[String, untyped]
  # @rbs return: Array[String]
  def send_rules(schema)
    schema.fetch('$defs').flat_map do |name, definition|
      sentences = descriptions(definition).flat_map { |text| text.gsub(/\s+/, ' ').split(/(?<=[.!?]) /) }
      sentences.grep(SEND_RULE).uniq.map { |sentence| "`#{name}`: #{sentence}" }
    end
  end

  # @rbs node: untyped
  # @rbs return: Array[String]
  def descriptions(node)
    case node
    when Hash
      [node['description']].grep(String) + node.values.flat_map { |child| descriptions(child) }
    when Array then node.flat_map { |child| descriptions(child) }
    else []
    end
  end

  # @rbs names: Array[String]
  # @rbs return: Array[String]
  def code(names) = names.map { |name| "`#{name}`" }

  # @rbs heading: String
  # @rbs categories: Array[SchemaDiff::Category]
  # @rbs return: String
  def section(heading, categories)
    listed = categories.reject { |category| category.items.empty? }
    body = listed.map { |category| "**#{category.title}**\n\n#{category.items.map { |item| "- #{item}" }.join("\n")}" }
    ["### #{heading}", *(body.empty? ? ['No changes.'] : body)].join("\n\n")
  end
end
