# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'rake/testtask'
require 'rbconfig'
require 'rubocop/rake_task'
require 'tmpdir'
require_relative 'codegen/schema_diff'
require_relative 'codegen/type_generator'

GEMSPEC = 'acp-sdk.gemspec'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

RuboCop::RakeTask.new(:lint) do |t|
  t.options = ['--ignore-parent-exclusion', *ENV.fetch('RUBOCOP_OPTS', '').split]
end

def write_types(dir)
  schemas = [JSON.parse(File.read('schema/schema.json')), JSON.parse(File.read('schema/schema.unstable.json'))]
  TypeGenerator.files(*schemas).each do |path, source|
    target = File.join(dir, path)
    mkdir_p File.dirname(target), verbose: false
    File.write(target, source)
  end
end

# Starting empty drops a deleted file's signatures.
def write_signatures(output)
  FileUtils.rm_rf(output)
  FileUtils.mkdir_p(output)
  sh 'rbs-inline', '--opt-out', "--output=#{output}", 'lib', 'codegen', verbose: false
end

desc 'Generate lib/acp/types from the vendored schemas, then sig/generated from the inline annotations'
task generate: %w[generate:types generate:rbs]

namespace :generate do
  desc 'Generate lib/acp/types from schema/schema.json and schema/schema.unstable.json'
  task :types do
    stale = Dir.children('lib/acp/types') - TypeGenerator::SUPPORT_FILES
    stale.each { |entry| rm_rf File.join('lib/acp/types', entry), verbose: false }
    write_types('lib/acp/types')
  end

  desc 'Generate RBS signatures from inline annotations'
  task :rbs do
    write_signatures('sig/generated')
  end

  desc 'Watch lib/ and codegen/ for changes and regenerate RBS files'
  task :watch do
    require 'guard'
    require 'guard/commander'

    Guard.start(no_interactions: true)
  end
end

def schema_edition(dir, suffix)
  SchemaDiff::Edition.new(
    schema: JSON.parse(File.read(File.join(dir, "schema#{suffix}.json"))),
    meta: JSON.parse(File.read(File.join(dir, "meta#{suffix}.json")))
  )
end

def schema_release(dir)
  SchemaDiff::Release.new(
    version: File.read(File.join(dir, 'VERSION')).strip,
    stable: schema_edition(dir, ''),
    unstable: schema_edition(dir, '.unstable')
  )
end

namespace :schema do
  desc 'Print, as Markdown, what changed from the schema directory BEFORE to the one AFTER'
  task :diff do
    puts SchemaDiff.markdown(schema_release(ENV.fetch('BEFORE')), schema_release(ENV.fetch('AFTER')))
  end
end

namespace :types do
  desc 'Fail if lib/acp/types is out of date with the vendored schemas'
  task :check do
    Dir.mktmpdir('types-check') do |dir|
      write_types(dir)
      TypeGenerator::SUPPORT_FILES.each { |f| FileUtils.cp("lib/acp/types/#{f}", dir) }
      sh "diff -ru lib/acp/types #{dir}" do |ok, _|
        abort 'lib/acp/types is out of date; run bin/generate and commit the result' unless ok
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

  desc 'Fail if sig/generated is out of date with lib/ or codegen/'
  task :check do
    FileUtils.mkdir_p(%w[tmp sig/generated])
    Dir.mktmpdir('rbs-check', 'tmp') do |dir|
      write_signatures(dir)
      sh 'diff', '-ru', 'sig/generated', dir do |ok, _|
        abort 'sig/generated is out of date; run bin/generate and commit the result' unless ok
      end
    end
  end

  desc 'Fail if a sig/manual file has no lib or codegen counterpart (file or Zeitwerk namespace dir)'
  task :lint_manual do
    stale = Dir['sig/manual/**/*.rbs'].reject do |file|
      source = file.delete_prefix('sig/manual/').sub(/\.rbs\z/, '.rb')
      source_path = source.start_with?('codegen/') ? source : "lib/#{source}"
      File.exist?(source_path) || Dir.exist?(source_path.delete_suffix('.rb'))
    end
    abort "sig/manual files without a lib or codegen counterpart: #{stale.join(', ')}" unless stale.empty?
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

desc 'Install the RBS collection'
task :setup do
  sh 'rbs collection install'
end

desc 'Build the gem into pkg/, then install it into an empty GEM_HOME and check it loads'
task :build do
  spec = Gem::Specification.load(GEMSPEC)
  # The gemspec leaves out the codegen/ signatures on purpose.
  shippable = Dir['lib/**/*.rb', 'sig/**/*.rbs'].grep_v(%r{\Asig/[^/]+/codegen/})
  missing = shippable - spec.files
  abort "#{GEMSPEC} leaves out #{missing.join(', ')}" unless missing.empty?

  gem_file = File.join('pkg', spec.file_name)
  FileUtils.mkdir_p(%w[pkg tmp])
  sh 'gem', 'build', GEMSPEC, '--output', gem_file

  Dir.mktmpdir('install', 'tmp') do |dir|
    gem_home = File.expand_path(dir)
    # The empty GEM_HOME receives only the built gem; its dependencies resolve
    # from the bundle's gem path, so --local never reaches the network.
    env = { 'GEM_HOME' => gem_home, 'GEM_PATH' => [gem_home, *Gem.path].join(File::PATH_SEPARATOR) }
    # Eager loading fails on a file that needs one the gem doesn't ship. The
    # unstable types are outside Zeitwerk, so they're required on their own.
    check = <<~RUBY
      require 'acp/sdk'
      spec = Gem.loaded_specs.fetch('acp-sdk')
      abort "loaded \#{spec.full_gem_path}, not the built gem" unless spec.full_gem_path.start_with?(ENV['GEM_HOME'])
      Zeitwerk::Loader.eager_load_all
      require 'acp/types/unstable'
      puts "loaded acp-sdk \#{ACP::VERSION} from the built gem"
    RUBY
    Bundler.with_unbundled_env do
      sh env, 'gem', 'install', '--local', '--no-document', gem_file
      sh env, RbConfig.ruby, '-e', check, verbose: false
    end
  end
end
