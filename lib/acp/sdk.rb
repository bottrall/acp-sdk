# frozen_string_literal: true

require 'zeitwerk'
require_relative 'version'

# The gem is `acp-sdk` but its namespace is `ACP`, so lib/acp is the root
# directory for ACP rather than lib for a top-level constant.
root = __dir__ #: String
loader = Zeitwerk::Loader.new
loader.tag = 'acp-sdk'
loader.push_dir(root, namespace: ACP)
loader.ignore(__FILE__, "#{root}/version.rb")
loader.setup
