# frozen_string_literal: true

require 'test_helper'
require_relative 'fixtures'

describe TypeGenerator::Resolve do
  schema = TypeGenerator::Schema.new(FixtureSchemas::STABLE.fetch('$defs'))

  it 'classifies each def kind' do
    kinds = FixtureSchemas::STABLE.fetch('$defs').to_h { |name, definition| [name, TypeGenerator::Resolve.kind(definition)] }

    assert_equal(
      {
        'WidgetRequest' => :object,
        'Step' => :object,
        'Note' => :object,
        'Mode' => :enum,
        'Choice' => :union,
        'Blend' => :union,
        'AnyList' => :array_union,
        'Amount' => :primitive_union,
        'Orphan' => :object
      },
      kinds
    )
  end

  it 'resolves a primitive union to a one_of check over the variant classes' do
    type = TypeGenerator::Resolve.resolve_ref(schema, 'Amount')

    assert_equal ['String | Integer', [:one_of, %w[String Integer], nil], false], [type.rbs, type.check, type.nullable?]
  end

  it 'resolves an enum ref to a closed enum check' do
    type = TypeGenerator::Resolve.resolve_ref(schema, 'Mode')

    assert_equal ['String', [:enum, %w[read write delete]]], [type.rbs, type.check]
  end

  it 'resolves a union ref to the union module type' do
    type = TypeGenerator::Resolve.resolve_ref(schema, 'Choice')

    assert_equal ['ACP::Types::Choice::t', [:object, 'ACP::Types::Choice']], [type.rbs, type.check]
  end

  it 'resolves an array-union ref to the union module type checked elementwise' do
    type = TypeGenerator::Resolve.resolve_ref(schema, 'AnyList')

    assert_equal ['ACP::Types::AnyList::t', [:objects, 'ACP::Types::AnyList']], [type.rbs, type.check]
  end
end
