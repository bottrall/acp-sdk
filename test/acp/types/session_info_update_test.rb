# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::SessionInfoUpdate do
  {
    'an explicit null that clears the field' => { 'title' => nil, 'updatedAt' => nil },
    'an absent key that leaves the field unchanged' => {},
    'a new value' => { 'title' => 'Implement user authentication', 'updatedAt' => '2026-09-28T10:00:00Z' }
  }.each do |description, payload|
    it "round-trips #{description}" do
      assert_equal payload, ACP::Types::SessionInfoUpdate.from_h(payload).to_h
    end

    it "round-trips #{description} as a session update" do
      update = payload.merge('sessionUpdate' => 'session_info_update')

      assert_equal update, ACP::Types::SessionUpdate.from_h(update).to_h
    end
  end

  it 'sends null for a field set to nil and omits one left unset' do
    assert_equal({ 'title' => nil }, ACP::Types::SessionInfoUpdate.new(title: nil).to_h)
  end
end
