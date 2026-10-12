# frozen_string_literal: true

require 'test_helper'
require_relative '../../../codegen/type_generator'

describe TypeGenerator::Plan do
  def plan = TypeGenerator::Plan

  def ref(name) = { '$ref' => "#/$defs/#{name}" }

  def object(*refs, **extra)
    properties = refs.to_h { |name| [name.downcase, ref(name)] }
    { 'type' => 'object', 'properties' => properties }.merge(extra.transform_keys(&:to_s))
  end

  def root(*refs) = object(*refs).merge('x-method' => true)

  def subsuming(tag, name)
    {
      'title' => tag.capitalize,
      'type' => 'object',
      'properties' => { 'type' => { 'type' => 'string', 'const' => tag } },
      'allOf' => [ref(name)],
      'required' => ['type']
    }
  end

  def schema(defs, **) = TypeGenerator::Schema.new(defs, **)

  def variant(defs, union) = TypeGenerator::Unions.variant_refs(defs, defs.const(union), defs.fetch(union)).first.last

  def requires(source) = source.scan(/^require_relative '(.+)'$/).flatten

  let(:alias_paths) { TypeGenerator::ALIASES.keys.map { |name| "#{plan.snake(name)}.rb" } }
  let(:stable) { { '$defs' => { 'Widget' => root('Step'), 'Step' => object, 'Orphan' => object } } }
  let(:unstable) do
    {
      '$defs' => stable.fetch('$defs').merge('Step' => object(title: 'Changed'), 'Gadget' => root, 'Stray' => object)
    }
  end
  let(:vessel) { { 'oneOf' => [subsuming('cup', 'Mug')] } }
  let(:shade) { { 'oneOf' => [subsuming('dim', 'Lamp'), subsuming('bright', 'Lamp')] } }

  describe '.files' do
    it 'emits the defs reachable from the x-method roots plus the aliases, sorted by path' do
      assert_equal (%w[step.rb widget.rb] + alias_paths).sort, plan.files(stable).keys
    end

    it 'aliases each name to its target in the stable namespace' do
      pass = schema(stable.fetch('$defs'))

      assert_equal TypeGenerator::ALIASES.to_h { |name, target| plan.alias_file(pass, name, pass.const(target)) },
                   plan.files(stable).slice(*alias_paths)
    end

    it 'adds the unstable files when given an unstable schema' do
      assert_equal %w[unstable.rb unstable/gadget.rb unstable/step.rb],
                   (plan.files(stable, unstable).keys - plan.files(stable).keys).sort
    end

    it 'leaves the stable files identical when given an unstable schema' do
      files = plan.files(stable)

      assert_equal files, plan.files(stable, unstable).slice(*files.keys)
    end
  end

  describe '.unstable_files' do
    it 'regenerates only the reachable defs the unstable schema changes or adds' do
      assert_equal %w[unstable.rb unstable/gadget.rb unstable/step.rb],
                   plan.unstable_files(stable.fetch('$defs'), unstable).keys.sort
    end

    it 'generates under the unstable header' do
      assert plan.unstable_files(stable.fetch('$defs'), unstable)
                 .fetch('unstable/step.rb')
                 .start_with?(TypeGenerator::UNSTABLE_HEADER)
    end

    it 'requires every file it generated, the aliases after the classes' do
      added = { '$defs' => stable.fetch('$defs').merge('Vessel' => vessel.merge('x-method' => true), 'Mug' => object) }
      files = plan.unstable_files(stable.fetch('$defs'), added)
      required = requires(files.fetch('unstable.rb'))

      assert_equal [files.except('unstable.rb').keys.map { |path| path.delete_suffix('.rb') }.sort, 'unstable/mug'],
                   [required.sort, required.last]
    end
  end

  describe '.opt_in_file' do
    it 'requires every path without its extension, classes before aliases' do
      file = plan.opt_in_file(%w[unstable/a.rb unstable/b.rb unstable/c.rb], %w[unstable/a.rb])

      assert_equal %w[unstable/b unstable/c unstable/a], requires(file.fetch('unstable.rb'))
    end

    it 'defines the unstable namespace before the requires' do
      source = plan.opt_in_file(%w[unstable/a.rb], []).fetch('unstable.rb')

      assert_operator source.index("module ACP::Types::Unstable\nend\n"), :<, source.index('require_relative')
    end
  end

  describe '.generate' do
    let(:ungenerated) { schema({ 'Vessel' => vessel, 'Mug' => object('Step'), 'Step' => object }, twins: %w[Step]) }
    let(:flattened) { TypeGenerator::FLATTENED_UNION_ATTRS.keys.first }
    let(:mode) do
      object(
        oneOf: [
          { 'title' => 'Session', 'type' => 'object', 'properties' => { 'sessionId' => { 'type' => 'string' } },
            'required' => ['sessionId'] },
          { 'title' => 'Request', 'type' => 'object', 'properties' => { 'requestId' => { 'type' => 'string' } },
            'required' => ['requestId'] }
        ]
      )
    end
    let(:nesting) { schema({ 'Vessel' => { 'oneOf' => [subsuming('cup', flattened)] }, flattened => mode }) }

    it 'emits only the defs reachable from the roots' do
      files, = plan.generate(schema(stable.fetch('$defs')), %w[Step])

      assert_equal %w[step.rb], files.keys
    end

    it 'skips reachable defs the schema does not generate' do
      files, = plan.generate(ungenerated, %w[Vessel])

      assert_equal %w[unstable/step.rb], files.keys
    end

    it 'resolves a normally reached def against the schema that knows what was subsumed' do
      cup = variant(nesting, 'Vessel')
      union = TypeGenerator::Resolve.definition_files(nesting.with_subsumed(flattened => cup), 'Vessel').to_h
      files, = plan.generate(nesting, %w[Vessel])

      refute_equal union, TypeGenerator::Resolve.definition_files(nesting, 'Vessel').to_h
      assert_equal union, files.slice(*union.keys)
    end

    it 'replaces only the class file of a subsumed def, keeping its nested union files' do
      cup = variant(nesting, 'Vessel')
      own, content = plan.alias_file(nesting, flattened, cup)
      resolved = TypeGenerator::Resolve.definition_files(nesting.with_subsumed(flattened => cup), flattened)
      nested = resolved.to_h.except(own)
      files, = plan.generate(nesting, %w[Vessel])

      refute_empty nested
      assert_equal nested.merge(own => content), files.slice(own, *nested.keys)
    end

    it 'emits a def one variant class subsumes as an alias of that variant' do
      pass = schema({ 'Vessel' => vessel, 'Mug' => object })
      files, = plan.generate(pass, %w[Vessel])

      assert_equal plan.alias_file(pass, 'Mug', variant(pass, 'Vessel')).last, files.fetch('mug.rb')
    end

    it 'drops a def several variant classes subsume' do
      pass = schema({ 'Shade' => shade, 'Lamp' => object })
      files, = plan.generate(pass, %w[Shade])

      assert_equal TypeGenerator::Resolve.definition_files(pass, 'Shade').map(&:first).sort, files.keys
    end

    it 'sorts the files by path' do
      files, = plan.generate(schema(stable.fetch('$defs')), %w[Widget])

      assert_equal %w[step.rb widget.rb], files.keys
    end

    it 'returns the paths of the aliases it emitted, sorted' do
      defs = { 'Vessel' => { 'oneOf' => [subsuming('cup', 'Mug'), subsuming('bowl', 'Dish')] },
               'Mug' => object, 'Dish' => object }

      assert_equal %w[dish.rb mug.rb], plan.generate(schema(defs), %w[Vessel]).last
    end

    it 'returns no alias path for a subsumed def the schema does not generate' do
      assert_empty plan.generate(ungenerated, %w[Vessel]).last
    end

    it 'returns no alias path for a def several variant classes subsume' do
      assert_empty plan.generate(schema({ 'Shade' => shade, 'Lamp' => object }), %w[Shade]).last
    end
  end

  describe '.reachable' do
    let(:chain) { schema({ 'Widget' => object('Step'), 'Step' => object }) }

    it 'returns what it has seen once nothing is pending' do
      assert_equal({ 'Step' => :normal }, plan.reachable(chain, [], { 'Step' => :normal }))
    end

    it 'keeps a normally reached def normal when a variant later claims it' do
      assert_equal({ 'Step' => :normal }, plan.reachable(chain, [['Step', :normal], ['Step', ['A']]], {}))
    end

    it 'collects every variant that claims a def' do
      assert_equal({ 'Step' => %w[A B] }, plan.reachable(chain, [['Step', ['A']], ['Step', ['B']]], {}))
    end

    it 'turns a claimed def normal when it is later reached normally' do
      assert_equal({ 'Step' => :normal }, plan.reachable(chain, [['Step', ['A']], ['Step', :normal]], {}))
    end

    it 'follows the edges of a def it has not seen' do
      assert_equal({ 'Widget' => :normal, 'Step' => :normal }, plan.reachable(chain, [['Widget', :normal]], {}))
    end

    it 'follows the edges of a claimed def' do
      assert_equal({ 'Widget' => ['A'], 'Step' => :normal }, plan.reachable(chain, [['Widget', ['A']]], {}))
    end
  end

  describe '.edges' do
    it 'lists plain refs as normal edges and subsumed refs as edges claimed by their variant' do
      option = subsuming('cup', 'Mug').merge('properties' => { 'type' => { 'const' => 'cup' }, 'lid' => ref('Lid') })
      defs = schema({ 'Vessel' => { 'oneOf' => [option] }, 'Mug' => object, 'Lid' => object })

      assert_equal [['Lid', :normal], ['Mug', [variant(defs, 'Vessel')]]], plan.edges(defs, 'Vessel')
    end
  end

  describe '.plain_refs' do
    it "skips a subsuming option's allOf ref but keeps the refs of its own properties" do
      option = subsuming('cup', 'Mug').merge('properties' => { 'lid' => ref('Lid') })

      assert_equal %w[Lid], plan.plain_refs(option)
    end

    it 'keeps the allOf ref of an option that does not subsume it' do
      assert_equal %w[Mug], plan.plain_refs({ 'allOf' => [ref('Mug')] })
    end

    it 'collects the refs nested anywhere in hashes and arrays' do
      node = { 'properties' => { 'steps' => { 'items' => ref('Step') } },
               'anyOf' => [ref('Note'), { 'type' => 'null' }] }

      assert_equal %w[Step Note], plan.plain_refs(node)
    end

    it 'finds no refs in a scalar' do
      assert_empty plan.plain_refs('string')
    end
  end

  describe '.subsumed_edges' do
    it 'pairs each ref a union variant subsumes with that variant' do
      defs = schema({ 'Vessel' => vessel, 'Mug' => object })

      assert_equal [['Mug', variant(defs, 'Vessel')]], plan.subsumed_edges(defs, 'Vessel')
    end

    it 'finds none in a def that is not a union' do
      assert_empty plan.subsumed_edges(schema({ 'Step' => object }), 'Step')
    end
  end

  describe '.ref_name' do
    it 'strips the $defs pointer prefix' do
      assert_equal 'Step', plan.ref_name('#/$defs/Step')
    end
  end

  describe '.path' do
    it 'maps a constant to its snake-cased path below the types namespace' do
      assert_equal 'unstable/tool_call/in_progress.rb', plan.path('ACP::Types::Unstable::ToolCall::InProgress')
    end
  end

  describe '.snake' do
    it 'snake-cases camel case, splitting after digits and dropping a leading underscore' do
      assert_equal(%w[mcp_servers http2_stream meta], %w[mcpServers Http2Stream _meta].map { |name| plan.snake(name) })
    end
  end

  describe '.camel' do
    it 'capitalizes the parts between non-alphanumeric separators' do
      assert_equal(%w[ToolCallUpdate Http2Stream], %w[tool_call_update http2-stream].map { |name| plan.camel(name) })
    end
  end

  describe '.alias_file' do
    it "assigns the target to the def's constant, declared to RBS as a class alias, under the schema header" do
      pass = schema({}, header: "# header\n", twins: %w[Mug])

      assert_equal ['unstable/mug.rb', <<~RUBY], plan.alias_file(pass, 'Mug', 'ACP::Types::Vessel::Cup')
        # header

        # @rbs!
        #   class ACP::Types::Unstable::Mug = ACP::Types::Vessel::Cup

        ACP::Types::Unstable::Mug = ACP::Types::Vessel::Cup
      RUBY
    end
  end
end
