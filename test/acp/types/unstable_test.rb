# frozen_string_literal: true

require 'test_helper'
require 'open3'

require 'acp/types/unstable'

describe 'ACP::Types::Unstable' do
  it 'stays unloaded until the caller opts in' do
    out, _err = Open3.capture3('bundle', 'exec', 'ruby', '-I', 'lib', '-e', <<~RUBY)
      require 'acp/sdk'
      puts "gate=\#{ACP::Types.unstable_enabled?}"
      begin
        ACP::Types::Unstable
        puts 'autoloaded'
      rescue NameError
        puts 'guarded'
      end
    RUBY
    assert_equal "gate=false\nguarded\n", out
  end

  it 'reports the opt-in gate as open once the unstable types are required' do
    assert_predicate ACP::Types, :unstable_enabled?
  end

  it 'parses PromptResponse usage' do
    response = ACP::Types::Unstable::PromptResponse.from_h(
      { 'stopReason' => 'end_turn',
        'usage' => { 'totalTokens' => 10, 'inputTokens' => 6, 'outputTokens' => 4 } }
    )

    assert_equal({ 'totalTokens' => 10, 'inputTokens' => 6, 'outputTokens' => 4 }, response.usage.to_h)
    assert_equal(
      { 'stopReason' => 'end_turn',
        'usage' => { 'totalTokens' => 10, 'inputTokens' => 6, 'outputTokens' => 4 } },
      response.to_h
    )
  end

  it 'dispatches the unstable session updates' do
    examples = {
      ACP::Types::Unstable::SessionUpdate::PlanRemoved => {
        'sessionUpdate' => 'plan_removed', 'planId' => 'plan_1'
      },
      ACP::Types::Unstable::SessionUpdate::Notice => {
        'sessionUpdate' => 'notice', 'severity' => 'info', 'title' => 'Rate limit reached'
      },
      ACP::Types::Unstable::SessionUpdate::CompactionUpdate => {
        'sessionUpdate' => 'compaction_update', 'compactionId' => 'compaction_1', 'status' => 'completed'
      },
      ACP::Types::Unstable::SessionUpdate::SubagentUpdate => {
        'sessionUpdate' => 'subagent_update', 'sessionId' => 'child_1', 'title' => 'Searcher'
      }
    }
    examples.each do |klass, example|
      assert_equal klass, ACP::Types::Unstable::SessionUpdate.from_h(example).class
      assert_equal example, klass.from_h(example).to_h
    end
  end

  it 'dispatches plan_update with markdown content' do
    example = {
      'sessionUpdate' => 'plan_update',
      'plan' => { 'type' => 'markdown', 'planId' => 'plan_1', 'content' => '# plan' }
    }
    update = ACP::Types::Unstable::SessionUpdate.from_h(example)

    assert_equal 'plan_1', update.plan.plan_id
    assert_equal '# plan', update.plan.content
    assert_equal example, update.to_h
  end

  it 'round-trips the keyword-named end field as the JSON key end' do
    example = { 'start' => { 'line' => 1, 'character' => 2 }, 'end' => { 'line' => 3, 'character' => 4 } }
    range = ACP::Types::Unstable::Range.from_h(example)

    assert_equal 1, range.start.line
    assert_equal 4, range.end_.character
    assert_equal example, range.to_h
  end

  it 'exposes the schema enum values as constants' do
    enums = {
      ACP::Types::Unstable::CompactionStatus => {
        'IN_PROGRESS' => 'in_progress', 'COMPLETED' => 'completed', 'FAILED' => 'failed', 'CANCELLED' => 'cancelled'
      },
      ACP::Types::Unstable::LlmProtocol => {
        'ANTHROPIC' => 'anthropic', 'OPENAI' => 'openai', 'AZURE' => 'azure', 'VERTEX' => 'vertex',
        'BEDROCK' => 'bedrock'
      },
      ACP::Types::Unstable::NesDiagnosticSeverity => {
        'ERROR' => 'error', 'WARNING' => 'warning', 'INFORMATION' => 'information', 'HINT' => 'hint'
      },
      ACP::Types::Unstable::NesRejectReason => {
        'REJECTED' => 'rejected', 'IGNORED' => 'ignored', 'REPLACED' => 'replaced', 'CANCELLED' => 'cancelled'
      },
      ACP::Types::Unstable::NesTriggerKind => {
        'AUTOMATIC' => 'automatic', 'DIAGNOSTIC' => 'diagnostic', 'MANUAL' => 'manual'
      },
      ACP::Types::Unstable::NoticeSeverity => { 'INFO' => 'info', 'WARNING' => 'warning', 'ERROR' => 'error' },
      ACP::Types::Unstable::PositionEncodingKind => { 'UTF_16' => 'utf-16', 'UTF_32' => 'utf-32', 'UTF_8' => 'utf-8' },
      ACP::Types::Unstable::TextDocumentSyncKind => { 'FULL' => 'full', 'INCREMENTAL' => 'incremental' }
    }
    enums.each do |enum_module, constants|
      constants.each { |name, value| assert_equal value, enum_module.const_get(name, false) }
    end
  end

  it 'leaves the stable SessionUpdate untouched by the unstable variants' do
    example = { 'sessionUpdate' => 'plan_removed', 'planId' => 'plan_1' }

    assert_equal example, ACP::Types::SessionUpdate.from_h(example)
  end
end
