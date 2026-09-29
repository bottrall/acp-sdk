# frozen_string_literal: true

require 'test_helper'

describe ACP do
  it 'eager-loads every file under lib/acp' do
    Zeitwerk::Loader.eager_load_all

    pass
  end

  it 'has a semantic version' do
    assert_match(/\A\d+\.\d+\.\d+\z/, ACP::VERSION)
  end
end
