# frozen_string_literal: true

require 'json'
require 'test_helper'
require_relative '../../codegen/type_generator'

describe 'type generator pipeline' do
  root = File.expand_path('../..', __dir__)
  types = File.join(root, 'lib/acp/types')

  it 'regenerates the committed lib/acp/types tree byte for byte, leaving the support files alone' do
    schemas = %w[schema/schema.json schema/schema.unstable.json]
              .map { |file| JSON.parse(File.read(File.join(root, file))) }
    committed = (Dir.glob('**/*.rb', base: types) - TypeGenerator::SUPPORT_FILES)
                .sort.to_h { |path| [path, File.read(File.join(types, path))] }

    assert_equal committed, TypeGenerator.files(*schemas)
  end
end
