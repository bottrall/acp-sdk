# frozen_string_literal: true

require 'test_helper'

describe ACP::Types::RequestPermissionResponse do
  let(:selected) { { 'outcome' => { 'outcome' => 'selected', 'optionId' => 'allow-once' } } }
  let(:cancelled) { { 'outcome' => { 'outcome' => 'cancelled' } } }

  it 'round-trips a selected outcome' do
    assert_equal selected, ACP::Types::RequestPermissionResponse.from_h(selected).to_h
  end

  it 'round-trips a cancelled outcome' do
    assert_equal cancelled, ACP::Types::RequestPermissionResponse.from_h(cancelled).to_h
  end

  it 'dispatches the outcome on its discriminator' do
    outcome = ACP::Types::RequestPermissionResponse.from_h(selected).outcome

    assert_instance_of ACP::Types::RequestPermissionOutcome::Selected, outcome
  end
end
