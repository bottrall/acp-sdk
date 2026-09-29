# frozen_string_literal: true

require_relative 'lib/acp/version'

Gem::Specification.new do |spec|
  spec.name = 'acp-sdk'
  spec.version = ACP::VERSION
  spec.authors = ['Jake Bottrall']
  spec.email = ['jakebottrall@gmail.com']

  spec.summary = 'A Ruby SDK for the Agent Client Protocol.'
  spec.description = 'An Agent Client Protocol (ACP) server for exposing agents and a client for driving them.'
  spec.homepage = 'https://github.com/bottrall/acp-sdk'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 4.0'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['changelog_uri'] = 'https://github.com/bottrall/acp-sdk/blob/main/CHANGELOG.md'
  spec.metadata['source_code_uri'] = spec.homepage

  spec.files = Dir['lib/**/*.rb', 'README.md', 'CHANGELOG.md', 'LICENSE.txt']
  spec.require_paths = ['lib']

  spec.add_dependency 'zeitwerk', '~> 2.8'
end
