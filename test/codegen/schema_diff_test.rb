# frozen_string_literal: true

require 'test_helper'
require_relative '../../codegen/schema_diff'

describe SchemaDiff do
  def diff = SchemaDiff

  let(:before) do
    SchemaDiff::Edition.new(
      schema: { '$defs' => { 'Kept' => { 'type' => 'string' }, 'Changed' => { 'type' => 'string' }, 'Gone' => {} } },
      meta: { 'version' => 1, 'agentMethods' => { 'old' => 'a/old', 'kept' => 'a/kept' } }
    )
  end
  let(:after) do
    SchemaDiff::Edition.new(
      schema: {
        '$defs' => {
          'Kept' => { 'type' => 'string' },
          'Changed' => { 'type' => 'integer' },
          'New' => { 'description' => 'Agents MUST only send this when asked.' }
        }
      },
      meta: { 'version' => 1, 'agentMethods' => { 'kept' => 'a/kept', 'new' => 'a/new' } }
    )
  end

  describe '.markdown' do
    it 'reports both sections, leaving out of the unstable one what the stable one lists' do
      unstable_before = before.with(schema: { '$defs' => before.schema['$defs'].merge('Draft' => {}) })
      unstable_after = after.with(schema: { '$defs' => after.schema['$defs'].merge('Draft' => { 'type' => 'null' }) })
      releases = [
        SchemaDiff::Release.new(version: '1.0.0', stable: before, unstable: unstable_before),
        SchemaDiff::Release.new(version: '1.1.0', stable: after, unstable: unstable_after)
      ]

      assert_equal <<~MARKDOWN.chomp, diff.markdown(*releases)
        ## ACP schema diff: 1.0.0 → 1.1.0

        ### Stable (`schema.json`, `meta.json`)

        **Methods added**

        - `a/new` (agentMethods)

        **Methods removed**

        - `a/old` (agentMethods)

        **Defs added**

        - `New`

        **Defs removed**

        - `Gone`

        **Defs changed**

        - `Changed`

        **New send rules**

        - `New`: Agents MUST only send this when asked.

        ### Unstable, beyond stable (`schema.unstable.json`, `meta.unstable.json`)

        **Defs changed**

        - `Draft`
      MARKDOWN
    end
  end

  describe '.changes' do
    def items(title) = diff.changes(before, after).find { |category| category.title == title }.items

    it 'lists the methods added' do
      assert_equal ['`a/new` (agentMethods)'], items('Methods added')
    end

    it 'lists the methods removed' do
      assert_equal ['`a/old` (agentMethods)'], items('Methods removed')
    end

    it 'lists the defs added' do
      assert_equal ['`New`'], items('Defs added')
    end

    it 'lists the defs removed' do
      assert_equal ['`Gone`'], items('Defs removed')
    end

    it 'lists the defs both schemas have that differ' do
      assert_equal ['`Changed`'], items('Defs changed')
    end

    it 'lists the send rules only the newer schema states' do
      assert_equal ['`New`: Agents MUST only send this when asked.'], items('New send rules')
    end
  end

  describe '.method_names' do
    it 'names each listed method with its section' do
      meta = { 'agentMethods' => { 'new' => 'session/new' }, 'clientMethods' => { 'kill' => 't/kill' } }

      assert_equal ['`session/new` (agentMethods)', '`t/kill` (clientMethods)'], diff.method_names(meta)
    end
  end

  describe '.methods_by_section' do
    it 'lists the methods of each section, skipping keys that are not sections' do
      meta = { 'version' => 1, 'agentMethods' => { 'new' => 'session/new' }, 'clientMethods' => { 'kill' => 't/kill' } }

      assert_equal({ 'agentMethods' => ['session/new'], 'clientMethods' => ['t/kill'] }, diff.methods_by_section(meta))
    end
  end

  describe '.send_rules' do
    def rules(description) = diff.send_rules({ '$defs' => { 'Update' => { 'description' => description } } })

    it 'keeps a sentence whose MUST or SHOULD is gated by only, unless or until' do
      description = "Agents MUST only send this\nupdate when asked. Agents MUST NOT send it unless asked. " \
                    'Clients MUST NOT send it until asked. Agents SHOULD only send it once.'

      assert_equal ['`Update`: Agents MUST only send this update when asked.',
                    '`Update`: Agents MUST NOT send it unless asked.',
                    '`Update`: Clients MUST NOT send it until asked.',
                    '`Update`: Agents SHOULD only send it once.'],
                   rules(description)
    end

    it 'keeps an "only send" sentence that has no keyword' do
      assert_equal ['`Update`: Only send this when asked.'], rules('Only send this when asked.')
    end

    it 'drops a sentence that gates nothing' do
      assert_empty rules('All agents MUST support text. It is only a hint.')
    end

    it "lists a sentence once per def when several of the def's descriptions repeat it" do
      schema = {
        '$defs' => {
          'Update' => { 'description' => 'Only send this when asked.',
                        'oneOf' => [{ 'description' => 'Only send this when asked.' }] }
        }
      }

      assert_equal ['`Update`: Only send this when asked.'], diff.send_rules(schema)
    end
  end

  describe '.descriptions' do
    it 'collects the description strings of nested hashes and arrays' do
      node = { 'description' => 'top', 'properties' => { 'a' => { 'description' => 'a' } },
               'anyOf' => [{ 'description' => 'b' }] }

      assert_equal %w[top a b], diff.descriptions(node)
    end

    it 'skips a description key that holds a property rather than text' do
      assert_equal ['inner'], diff.descriptions({ 'description' => { 'description' => 'inner' } })
    end
  end

  describe '.code' do
    it 'wraps each name in backticks' do
      assert_equal %w[`A` `B`], diff.code(%w[A B])
    end
  end

  describe '.section' do
    it 'lists each category that has items under the heading' do
      categories = [SchemaDiff::Category.new(title: 'Added', items: %w[a b]),
                    SchemaDiff::Category.new(title: 'Gone', items: [])]

      assert_equal "### Head\n\n**Added**\n\n- a\n- b", diff.section('Head', categories)
    end

    it 'says there are no changes when every category is empty' do
      assert_equal "### Head\n\nNo changes.", diff.section('Head', [SchemaDiff::Category.new(title: 'Gone', items: [])])
    end
  end
end
