# frozen_string_literal: true

require 'test_helper'

describe 'ACP::Types enum constant modules' do
  # No generated class references these modules: they are public API for
  # building requests and matching responses without string literals. The
  # table pins each module's constants so the pattern stays deliberate.
  let(:enums) do
    {
      ACP::Types::ElicitationSchemaType => { 'OBJECT' => 'object' },
      ACP::Types::PlanEntryPriority => { 'HIGH' => 'high', 'MEDIUM' => 'medium', 'LOW' => 'low' },
      ACP::Types::PlanEntryStatus => {
        'PENDING' => 'pending', 'IN_PROGRESS' => 'in_progress', 'COMPLETED' => 'completed'
      },
      ACP::Types::Role => { 'ASSISTANT' => 'assistant', 'USER' => 'user' },
      ACP::Types::SessionConfigOptionCategory => {
        'MODE' => 'mode', 'MODEL' => 'model', 'MODEL_CONFIG' => 'model_config', 'THOUGHT_LEVEL' => 'thought_level'
      },
      ACP::Types::StringFormat => { 'EMAIL' => 'email', 'URI' => 'uri', 'DATE' => 'date', 'DATE_TIME' => 'date-time' },
      ACP::Types::ToolCallStatus => {
        'PENDING' => 'pending', 'IN_PROGRESS' => 'in_progress', 'COMPLETED' => 'completed', 'FAILED' => 'failed'
      },
      ACP::Types::PermissionOptionKind => {
        'ALLOW_ONCE' => 'allow_once', 'ALLOW_ALWAYS' => 'allow_always',
        'REJECT_ONCE' => 'reject_once', 'REJECT_ALWAYS' => 'reject_always'
      },
      ACP::Types::StopReason => {
        'END_TURN' => 'end_turn', 'MAX_TOKENS' => 'max_tokens',
        'MAX_TURN_REQUESTS' => 'max_turn_requests', 'REFUSAL' => 'refusal', 'CANCELLED' => 'cancelled'
      },
      ACP::Types::ToolKind => {
        'READ' => 'read', 'EDIT' => 'edit', 'DELETE' => 'delete', 'MOVE' => 'move', 'SEARCH' => 'search',
        'EXECUTE' => 'execute', 'THINK' => 'think', 'FETCH' => 'fetch', 'SWITCH_MODE' => 'switch_mode',
        'OTHER' => 'other'
      }
    }
  end

  it 'exposes the schema enum values as constants' do
    enums.each do |enum_module, constants|
      constants.each { |name, value| assert_equal value, enum_module.const_get(name, false) }
    end
  end
end
