# frozen_string_literal: true

D = Steep::Diagnostic

target :lib do
  signature 'sig/generated'
  signature 'sig/manual'
  signature 'sig/_private'

  check 'lib'

  collection_config 'rbs_collection.yaml'

  configure_code_diagnostics(D::Ruby.all_error)
end
