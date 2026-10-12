# frozen_string_literal: true

require 'test_helper'
require_relative '../../codegen/type_generator'

describe TypeGenerator do
  describe TypeGenerator::Type do
    it 'defaults to a frozen, non-nullable type with no conversions or check' do
      type = TypeGenerator::Type.new(rbs: 'String')

      assert_equal ['String', nil, nil, false, nil, true],
                   [type.rbs, type.from, type.to, type.nullable?, type.check, type.frozen?]
    end
  end

  describe TypeGenerator::Field do
    type = TypeGenerator::Type.new(rbs: 'String')

    it 'defaults to a frozen field with no JSON key that is neither clearable nor flattened' do
      field = TypeGenerator::Field.new(attr: 'label', type:, required: true, nullable: false)

      assert_equal [nil, false, false, true], [field.json, field.clearable?, field.flattened?, field.frozen?]
    end

    it 'is not nilable when required and not nullable' do
      refute_predicate TypeGenerator::Field.new(attr: 'label', type:, required: true, nullable: false), :nilable?
    end

    it 'is nilable when optional' do
      assert_predicate TypeGenerator::Field.new(attr: 'label', type:, required: false, nullable: false), :nilable?
    end

    it 'is nilable when required but nullable' do
      assert_predicate TypeGenerator::Field.new(attr: 'label', type:, required: true, nullable: true), :nilable?
    end
  end

  describe TypeGenerator::Schema do
    defs = { 'Step' => { 'type' => 'object' }, 'Mug' => { 'type' => 'object' } }
    stable = TypeGenerator::Schema.new(defs)
    unstable = TypeGenerator::Schema.new(defs, header: TypeGenerator::UNSTABLE_HEADER, twins: ['Step'])

    it 'defaults to a frozen schema with the stable header' do
      assert_equal [TypeGenerator::HEADER, true], [stable.header, stable.frozen?]
    end

    it 'fetches a def by name' do
      assert_same defs.fetch('Step'), stable.fetch('Step')
    end

    describe '#const' do
      it 'names a def under the stable namespace when the schema has no twins' do
        assert_equal 'ACP::Types::Step', stable.const('Step')
      end

      it 'names a twin under the unstable namespace' do
        assert_equal 'ACP::Types::Unstable::Step', unstable.const('Step')
      end

      it 'names a def that is not a twin under the stable namespace' do
        assert_equal 'ACP::Types::Mug', unstable.const('Mug')
      end
    end

    describe '#generated?' do
      it 'generates every def when the schema has no twins' do
        assert stable.generated?('Step')
      end

      it 'generates a twin' do
        assert unstable.generated?('Step')
      end

      it 'does not generate a def that is not a twin' do
        refute unstable.generated?('Mug')
      end
    end

    describe '#nested_const' do
      it 'is the def constant when nothing is subsumed' do
        assert_equal 'ACP::Types::Unstable::Step', unstable.nested_const('Step')
      end

      it 'is the variant constant that absorbed a subsumed def' do
        subsumed = stable.with_subsumed('Mug' => 'ACP::Types::Vessel::Cup')

        assert_equal 'ACP::Types::Vessel::Cup', subsumed.nested_const('Mug')
      end

      it 'is the def constant for a def that is not subsumed' do
        subsumed = unstable.with_subsumed('Mug' => 'ACP::Types::Vessel::Cup')

        assert_equal 'ACP::Types::Unstable::Step', subsumed.nested_const('Step')
      end
    end

    describe '#with_subsumed' do
      it 'keeps the defs, header and twins' do
        subsumed = unstable.with_subsumed('Mug' => 'ACP::Types::Vessel::Cup')

        assert_equal [defs.fetch('Step'), TypeGenerator::UNSTABLE_HEADER, 'ACP::Types::Unstable::Step', false],
                     [subsumed.fetch('Step'), subsumed.header, subsumed.const('Step'), subsumed.generated?('Mug')]
      end
    end
  end

  describe TypeGenerator::Dispatch do
    it 'is frozen' do
      assert_predicate TypeGenerator::Dispatch.new(tag: 'type', tagged: [], untagged: []), :frozen?
    end
  end

  describe '.files' do
    stable = { '$defs' => { 'Step' => {} } }
    unstable = { '$defs' => { 'Mug' => {} } }
    forwarded = lambda do |*schemas|
      TypeGenerator::Plan.define_singleton_method(:files) { |*args| args }
      TypeGenerator.files(*schemas)
    ensure
      TypeGenerator::Plan.singleton_class.send(:remove_method, :files)
    end

    it 'hands the planner the stable schema and no unstable one' do
      assert_equal [stable, nil], forwarded.call(stable)
    end

    it 'hands the planner the stable and unstable schemas in order' do
      assert_equal [stable, unstable], forwarded.call(stable, unstable)
    end
  end
end
