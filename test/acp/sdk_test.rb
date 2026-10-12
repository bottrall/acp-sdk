# frozen_string_literal: true

require 'test_helper'
require 'open3'

describe ACP do
  # Bundler evaluates the gemspec, which loads version.rb and defines ACP
  # before the SDK is required, so the child runs without it.
  def run_in_child(script)
    load_path = [File.expand_path('../../lib', __dir__), *Gem.loaded_specs.fetch('zeitwerk').full_require_paths]
    includes = load_path.flat_map { |path| ['-I', path] }
    env = { 'RUBYOPT' => nil, 'BUNDLER_SETUP' => nil }
    Open3.capture3(env, RbConfig.ruby, *includes, '-e', "require 'acp/sdk'\n#{script}")
  end

  def eager_load_failure
    run_in_child(<<~RUBY)
      begin
        Zeitwerk::Loader.eager_load_all
      rescue NameError => e
        print e.name
      end
    RUBY
  end

  def unstable_autoload_source
    run_in_child('print File.basename(ACP::Types.autoload?(:Unstable, false).to_s)')
  end

  it 'defines ACP::VERSION when nothing else has loaded version.rb' do
    out, err, status = run_in_child('print ACP.const_defined?(:VERSION, false)')

    assert_predicate status, :success?, err
    assert_equal 'true', out
  end

  it 'keeps sdk.rb out of the eager load' do
    out, err, status = eager_load_failure

    assert_predicate status, :success?, err
    refute_equal 'Sdk', out
  end

  it 'keeps version.rb out of the eager load' do
    out, err, status = eager_load_failure

    assert_predicate status, :success?, err
    refute_equal 'Version', out
  end

  it 'does not map types/unstable.rb to ACP::Types::Unstable' do
    out, err, status = unstable_autoload_source

    assert_predicate status, :success?, err
    refute_equal 'unstable.rb', out
  end

  it 'does not map the types/unstable directory to ACP::Types::Unstable' do
    out, err, status = unstable_autoload_source

    assert_predicate status, :success?, err
    refute_equal 'unstable', out
  end
end
