# frozen_string_literal: true

require 'zeitwerk'
require_relative 'version'

# The gem is `acp-sdk` but its namespace is `ACP`, so lib/acp is the root
# directory for ACP rather than lib for a top-level constant.
root = __dir__ #: String
loader = Zeitwerk::Loader.new
loader.tag = 'acp-sdk'
loader.push_dir(root, namespace: ACP)
# The unstable types load only through `require 'acp/types/unstable'`, so
# Zeitwerk must not map them.
loader.ignore(__FILE__, "#{root}/version.rb", "#{root}/types/unstable.rb", "#{root}/types/unstable")
loader.setup
