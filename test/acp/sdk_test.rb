# frozen_string_literal: true

require 'test_helper'
require 'open3'

describe ACP do
  it 'eager-loads every file under lib/acp' do
    Zeitwerk::Loader.eager_load_all

    pass
  end

  it 'leaves the unstable types unloaded until the caller opts in' do
    out, _err = Open3.capture3('bundle', 'exec', 'ruby', '-I', 'lib', '-e', <<~RUBY)
      require 'acp/sdk'
      begin
        ACP::Types::Unstable
        print 'autoloaded'
      rescue NameError
        print 'guarded'
      end
    RUBY

    assert_equal 'guarded', out
  end

  it 'has a semantic version' do
    assert_match(/\A\d+\.\d+\.\d+\z/, ACP::VERSION)
  end
end
