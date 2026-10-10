# frozen_string_literal: true

require 'json'
require 'test_helper'
require_relative '../../codegen/type_generator'

# Content is already pinned byte-for-byte by `types:check`; this pins the file
# set so a pipeline regression surfaces as a Minitest failure, not a rake diff.
describe TypeGenerator do
  let(:root) { File.expand_path('../..', __dir__) }
  let(:generated_paths) do
    schemas = %w[schema/schema.json schema/schema.unstable.json]
              .map { |file| JSON.parse(File.read(File.join(root, file))) }
    TypeGenerator.files(*schemas).keys.sort
  end
  let(:committed_paths) { Dir.glob('**/*.rb', base: File.join(root, 'lib/acp/types')).sort }

  it 'generates exactly the committed lib/acp/types tree from the vendored schemas' do
    assert_equal committed_paths, generated_paths
  end
end