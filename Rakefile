# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'
require 'rubocop/rake_task'
require 'json'
require 'tmpdir'
require_relative 'codegen/type_generator'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

RuboCop::RakeTask.new do |t|
  t.options = ENV.fetch('RUBOCOP_OPTS', '').split
end

def write_types(dir)
  TypeGenerator.files(JSON.parse(File.read('schema/schema.json'))).each do |path, source|
    target = File.join(dir, path)
    mkdir_p File.dirname(target), verbose: false
    File.write(target, source)
  end
end

namespace :types do
  desc 'Generate lib/acp/types from schema/schema.json'
  task :generate do
    rm_rf 'lib/acp/types', verbose: false
    write_types('lib/acp/types')
  end

  desc 'Fail if lib/acp/types is out of date with schema/schema.json'
  task :check do
    Dir.mktmpdir('types-check') do |dir|
      write_types(dir)
      sh "diff -ru lib/acp/types #{dir}" do |ok, _|
        abort 'lib/acp/types is out of date; run bin/types and commit the result' unless ok
      end
    end
  end
end

namespace :rbs do
  desc 'Fail if rbs_collection.lock.yaml is out of date with rbs_collection.yaml or Gemfile.lock'
  task :collection_check do
    before = File.read('rbs_collection.lock.yaml')
    sh 'rbs collection update', verbose: false
    after = File.read('rbs_collection.lock.yaml')
    if before != after
      File.write('rbs_collection.lock.yaml', before)
      abort 'rbs_collection.lock.yaml is out of date; run `rbs collection update` and commit the result'
    end
  end

  desc 'Generate RBS signatures from inline annotations'
  task :generate do
    sh 'rbs-inline --opt-out --output=sig/generated lib'
  end

  desc 'Fail if sig/generated is out of date with lib/'
  task :check do
    Dir.mktmpdir('rbs-check') do |dir|
      sh "rbs-inline --opt-out --output=#{dir} lib", verbose: false
      sh "diff -ru sig/generated #{dir}" do |ok, _|
        abort 'sig/generated is out of date; run bin/rbs and commit the result' unless ok
      end
    end
  end

  desc 'Fail if a sig/manual file has no lib counterpart (file or Zeitwerk namespace dir)'
  task :lint_manual do
    stale = Dir['sig/manual/**/*.rbs'].reject do |file|
      lib_path = file.sub('sig/manual/', 'lib/').sub(/\.rbs\z/, '.rb')
      File.exist?(lib_path) || Dir.exist?(lib_path.delete_suffix('.rb'))
    end
    abort "sig/manual files without a lib counterpart: #{stale.join(', ')}" unless stale.empty?
  end

  desc 'Watch lib/ for changes and regenerate RBS files'
  task :watch do
    require 'guard'
    require 'guard/commander'

    Guard.start(no_interactions: true)
  end
end

namespace :steep do
  desc 'Type-check with Steep'
  task :check do
    # --no-daemon: Steep 2.1 otherwise routes the check through whatever
    # language server holds the project socket, including orphaned ones,
    # which can hang or report stale results.
    sh "steep check --no-daemon #{ENV.fetch('STEEP_OPTS', '')}".strip
  end
end

desc 'Check generated types and RBS signatures are current, then type-check'
task typecheck: %w[types:check rbs:check rbs:collection_check rbs:lint_manual steep:check]

desc 'Run everything CI runs'
task ci: %i[test rubocop typecheck]

task default: :ci
