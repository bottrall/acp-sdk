# frozen_string_literal: true

require 'test_helper'

describe ACP::RequestError do
  it 'builds parse errors with code -32700' do
    error = ACP::RequestError.parse_error

    assert_equal [-32_700, 'Parse error', nil], [error.code, error.message, error.data]
  end

  it 'builds invalid request errors with code -32600' do
    error = ACP::RequestError.invalid_request

    assert_equal [-32_600, 'Invalid request', nil], [error.code, error.message, error.data]
  end

  it 'builds method not found errors with code -32601' do
    error = ACP::RequestError.method_not_found

    assert_equal [-32_601, 'Method not found', nil], [error.code, error.message, error.data]
  end

  it 'builds invalid params errors with code -32602' do
    error = ACP::RequestError.invalid_params

    assert_equal [-32_602, 'Invalid params', nil], [error.code, error.message, error.data]
  end

  it 'builds internal errors with code -32603' do
    error = ACP::RequestError.internal_error

    assert_equal [-32_603, 'Internal error', nil], [error.code, error.message, error.data]
  end

  it 'builds request cancelled errors with code -32800' do
    error = ACP::RequestError.request_cancelled

    assert_equal [-32_800, 'Request cancelled', nil], [error.code, error.message, error.data]
  end

  it 'builds auth required errors with code -32000' do
    error = ACP::RequestError.auth_required

    assert_equal [-32_000, 'Authentication required', nil], [error.code, error.message, error.data]
  end

  it 'builds resource not found errors with the uri in data' do
    error = ACP::RequestError.resource_not_found('file:///a.txt')

    assert_equal [-32_002, 'Resource not found', { uri: 'file:///a.txt' }], [error.code, error.message, error.data]
  end

  it 'builds resource not found errors without data when no uri is given' do
    error = ACP::RequestError.resource_not_found

    assert_equal [-32_002, 'Resource not found', nil], [error.code, error.message, error.data]
  end
end
