# frozen_string_literal: true

require_relative '../../../codegen/type_generator'

# Hand-written fixture schemas for the codegen tests. Each def exercises one
# emitter branch (object, union, array_union, enum, primitive_union); the
# shapes mirror what schemars emits for the vendored ACP schemas. Def names
# are synthetic so they can be evaluated into ACP::Types without colliding
# with the generated classes.
module FixtureSchemas
  STABLE = {
    '$defs' => {
      'WidgetRequest' => {
        'type' => 'object',
        'x-method' => true,
        'properties' => {
          'label' => { 'type' => 'string' },
          'count' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => 100 },
          'steps' => { 'type' => 'array', 'items' => { '$ref' => '#/$defs/Step' } },
          'mode' => { '$ref' => '#/$defs/Mode' },
          'choice' => { '$ref' => '#/$defs/Choice' },
          'blend' => { '$ref' => '#/$defs/Blend' },
          'listing' => { '$ref' => '#/$defs/AnyList' },
          'amount' => { '$ref' => '#/$defs/Amount' }
        },
        'required' => ['label']
      },
      'Step' => {
        'type' => 'object',
        'properties' => { 'index' => { 'type' => 'integer' } },
        'required' => ['index']
      },
      'Note' => {
        'type' => 'object',
        'properties' => { 'text' => { 'type' => 'string' } },
        'required' => ['text']
      },
      'Mode' => {
        'oneOf' => [
          { 'type' => 'string', 'const' => 'read' },
          { 'type' => 'string', 'const' => 'write' },
          { 'type' => 'string', 'const' => 'delete' }
        ]
      },
      'Choice' => {
        'oneOf' => [
          {
            'title' => 'Read', 'type' => 'object',
            'properties' => { 'kind' => { 'type' => 'string', 'const' => 'read' } },
            'required' => ['kind']
          },
          {
            'title' => 'Write', 'type' => 'object',
            'properties' => { 'kind' => { 'type' => 'string', 'const' => 'write' }, 'text' => { 'type' => 'string' } },
            'required' => %w[kind text]
          }
        ]
      },
      'Blend' => {
        'oneOf' => [
          {
            'title' => 'Tagged', 'type' => 'object',
            'properties' => { 'type' => { 'type' => 'string', 'const' => 'tagged' } },
            'required' => ['type']
          },
          {
            'title' => 'Plain', 'type' => 'object',
            'properties' => { 'note' => { 'type' => 'string' } },
            'required' => ['note']
          }
        ]
      },
      'AnyList' => {
        'anyOf' => [
          { 'title' => 'Steps', 'type' => 'array', 'items' => { '$ref' => '#/$defs/Step' } },
          { 'title' => 'Notes', 'type' => 'array', 'items' => { '$ref' => '#/$defs/Note' } }
        ]
      },
      'Amount' => { 'oneOf' => [{ 'type' => 'string' }, { 'type' => 'integer' }] },
      'Orphan' => { 'type' => 'object', 'properties' => { 'ghost' => { 'type' => 'string' } } }
    }
  }.freeze

  # The unstable schema shares every def with STABLE except: Step gains a
  # `name` property (a twin to regenerate) and Gadget is unique to it.
  UNSTABLE = {
    '$defs' => STABLE['$defs'].merge(
      'Step' => {
        'type' => 'object',
        'properties' => { 'index' => { 'type' => 'integer' }, 'name' => { 'type' => 'string' } },
        'required' => ['index']
      },
      'Gadget' => {
        'type' => 'object',
        'x-method' => true,
        'properties' => { 'note' => { 'type' => 'string' } },
        'required' => ['note']
      }
    )
  }.freeze

  FILES = TypeGenerator.files(STABLE).freeze
  ALL_FILES = TypeGenerator.files(STABLE, UNSTABLE).freeze
end
