# frozen_string_literal: true

require 'zeitwerk'
require_relative 'version'

# The gem is `acp-sdk` but its namespace is `ACP`, so lib/acp is the root
# directory for ACP rather than lib for a top-level constant.
loader = Zeitwerk::Loader.new
loader.tag = 'acp-sdk'
loader.push_dir(__dir__, namespace: ACP)
loader.ignore(__FILE__, "#{__dir__}/version.rb")
loader.setup
