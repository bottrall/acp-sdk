# frozen_string_literal: true

require_relative 'lib/acp/version'

Gem::Specification.new do |spec|
  spec.name = 'acp-sdk'
  spec.version = ACP::VERSION
  spec.authors = ['Jake Bottrall']
  spec.email = ['jakebottrall@gmail.com']

  spec.summary = 'A Ruby SDK for the Agent Client Protocol.'
  spec.homepage = 'https://github.com/bottrall/acp-sdk'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['changelog_uri'] = 'https://github.com/bottrall/acp-sdk/blob/main/CHANGELOG.md'
  spec.metadata['source_code_uri'] = spec.homepage

  # sig/_private ships too: RBS skips `_`-prefixed directories when the gem's
  # signatures are loaded as a library, so its stubs stay private. The codegen/
  # signatures type-check the generator, which doesn't ship.
  shippable = Dir['lib/**/*.rb', 'sig/**/*.rbs', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.files = shippable.grep_v(%r{\Asig/[^/]+/codegen/})
  spec.require_paths = ['lib']

  spec.add_dependency 'zeitwerk', '~> 2.8'
end
