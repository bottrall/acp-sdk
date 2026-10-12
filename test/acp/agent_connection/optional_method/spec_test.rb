# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalMethod::Spec do
  response_class = Struct.new(:capabilities)
  capabilities_class = Struct.new(:flag)

  build = lambda { |path|
    ACP::AgentConnection::OptionalMethod::Spec.new(rpc_method: 'thing/do', agent_method: :do_thing, path:)
  }

  describe '#initialize' do
    it 'exposes what it was built with' do
      spec = build.call(%i[capabilities flag])

      assert_equal 'thing/do', spec.rpc_method
      assert_equal :do_thing, spec.agent_method
      assert_equal %i[capabilities flag], spec.path
    end

    it 'is frozen, including its path' do
      spec = build.call(%i[capabilities flag])

      assert_predicate spec, :frozen?
      assert_predicate spec.path, :frozen?
    end
  end

  describe '#advertised?' do
    it 'is true when the path leads to a truthy value' do
      response = response_class.new(capabilities_class.new(Object.new))

      assert_same true, build.call(%i[capabilities flag]).advertised?(response)
    end

    it 'is false when the path leads to nil' do
      response = response_class.new(capabilities_class.new(nil))

      assert_same false, build.call(%i[capabilities flag]).advertised?(response)
    end

    it 'is false when the path leads to false' do
      response = response_class.new(capabilities_class.new(false))

      assert_same false, build.call(%i[capabilities flag]).advertised?(response)
    end

    it 'is false when a node along the path lacks the reader' do
      response = response_class.new(Object.new)

      assert_same false, build.call(%i[capabilities flag]).advertised?(response)
    end

    it 'is false when a node along the path is nil' do
      response = response_class.new(nil)

      assert_same false, build.call(%i[capabilities flag]).advertised?(response)
    end
  end
end
