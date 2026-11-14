# frozen_string_literal: true

guard :shell do
  watch(%r{^(lib|codegen)/.*\.rb$}) do
    system('bundle exec rake generate:rbs')
  end
end
