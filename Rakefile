# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'
require 'rubocop/rake_task'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

RuboCop::RakeTask.new do |t|
  t.options = ENV.fetch('RUBOCOP_OPTS', '').split
end

desc 'Run everything CI runs'
task ci: %i[test rubocop]

task default: :ci
