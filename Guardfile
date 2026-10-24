# frozen_string_literal: true

guard :shell do
  watch(%r{^(lib|codegen)/.*\.rb$}) do
    system('bin/rbs')
  end
end
