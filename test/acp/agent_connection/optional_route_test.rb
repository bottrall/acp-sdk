# frozen_string_literal: true

require 'test_helper'

describe ACP::AgentConnection::OptionalRoute do
  response_class = Struct.new(:capabilities)
  capabilities_class = Struct.new(:flag)

  build = lambda { |path, &handle|
    ACP::AgentConnection::OptionalRoute.new(
      rpc_method: 'thing/do', type: ACP::Types::LogoutRequest, agent_method: :do_thing, path:, &handle
    )
  }

  describe '#initialize' do
    it 'exposes what it was built with' do
      handle = ->(_agent, _request) {}
      route = build.call(%i[capabilities flag], &handle)

      assert_equal(
        ['thing/do', ACP::Types::LogoutRequest, :do_thing, %i[capabilities flag], handle],
        [route.rpc_method, route.type, route.agent_method, route.path, route.handle]
      )
    end

    it 'is frozen, including its path' do
      route = build.call(%i[capabilities flag])

      assert_equal [true, true], [route.frozen?, route.path.frozen?]
    end

    it 'keeps a nil path for a per-session method' do
      assert_nil build.call(nil).path
    end
  end

  describe '#advertised?' do
    it 'is false for a per-session method, which initialize never advertises' do
      response = response_class.new(capabilities_class.new(true))

      assert_same false, build.call(nil).advertised?(response)
    end

    it 'follows its path through the initialize response' do
      answers = [true, false].map do |flag|
        build.call(%i[capabilities flag]).advertised?(response_class.new(capabilities_class.new(flag)))
      end

      assert_equal [true, false], answers
    end
  end

  describe '#routed?' do
    defining = Object.new
    def defining.do_thing(_request); end

    it 'follows the advertisement when there is a path, whatever the agent defines' do
      advertised = response_class.new(capabilities_class.new(true))
      unadvertised = response_class.new(capabilities_class.new(false))
      route = build.call(%i[capabilities flag])

      assert_equal [true, false], [route.routed?(advertised, Object.new), route.routed?(unadvertised, defining)]
    end

    it 'follows whether the agent defines the method for a per-session method' do
      response = response_class.new(nil)
      route = build.call(nil)

      assert_equal [true, false], [route.routed?(response, defining), route.routed?(response, Object.new)]
    end
  end
end
