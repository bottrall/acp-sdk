# frozen_string_literal: true

require 'test_helper'

describe ACP::RequestError do
  describe '#initialize' do
    it 'defaults data to nil' do
      error = ACP::RequestError.new(code: 1, message: 'Boom')

      assert_equal [1, 'Boom', nil], [error.code, error.message, error.data]
    end

    it 'freezes the error' do
      error = ACP::RequestError.new(code: 1, message: 'Boom', data: { detail: 'x' })

      assert_predicate error, :frozen?
    end
  end

  describe '#to_h' do
    it 'omits data when there is none' do
      error = ACP::RequestError.new(code: 1, message: 'Boom')

      assert_equal({ 'code' => 1, 'message' => 'Boom' }, error.to_h)
    end

    it 'includes data when it is given' do
      error = ACP::RequestError.new(code: 1, message: 'Boom', data: { detail: 'x' })

      assert_equal({ 'code' => 1, 'message' => 'Boom', 'data' => { detail: 'x' } }, error.to_h)
    end

    it 'keeps data that is false' do
      error = ACP::RequestError.new(code: 1, message: 'Boom', data: false)

      assert_equal({ 'code' => 1, 'message' => 'Boom', 'data' => false }, error.to_h)
    end
  end

  describe '#connection_closed?' do
    it 'is true for the closed-connection sentinel' do
      assert_predicate ACP::RequestError::CONNECTION_CLOSED, :connection_closed?
    end

    it 'is false for another error with the same code and message' do
      sentinel = ACP::RequestError::CONNECTION_CLOSED
      error = ACP::RequestError.new(code: sentinel.code, message: sentinel.message)

      refute_predicate error, :connection_closed?
    end
  end

  describe '.parse_error' do
    it 'builds a -32700 error' do
      error = ACP::RequestError.parse_error

      assert_equal [-32_700, 'Parse error', nil], [error.code, error.message, error.data]
    end
  end

  describe '.invalid_request' do
    it 'builds a -32600 error' do
      error = ACP::RequestError.invalid_request

      assert_equal [-32_600, 'Invalid request', nil], [error.code, error.message, error.data]
    end
  end

  describe '.method_not_found' do
    it 'builds a -32601 error without data when no method is given' do
      error = ACP::RequestError.method_not_found

      assert_equal [-32_601, 'Method not found', nil], [error.code, error.message, error.data]
    end

    it 'names the refused method in data' do
      error = ACP::RequestError.method_not_found('fs/read')

      assert_equal [-32_601, 'Method not found', { method: 'fs/read' }], [error.code, error.message, error.data]
    end
  end

  describe '.invalid_params' do
    it 'builds a -32602 error without data when no errors are given' do
      error = ACP::RequestError.invalid_params

      assert_equal [-32_602, 'Invalid params', nil], [error.code, error.message, error.data]
    end

    it 'carries the errors in data' do
      error = ACP::RequestError.invalid_params(['cwd: required'])

      assert_equal [-32_602, 'Invalid params', { errors: ['cwd: required'] }], [error.code, error.message, error.data]
    end
  end

  describe '.unadvertised' do
    it 'builds a -32601 error naming the capability the client lacks' do
      error = ACP::RequestError.unadvertised('fs.readTextFile')

      assert_equal(
        [-32_601, 'Client does not advertise fs.readTextFile', nil],
        [error.code, error.message, error.data]
      )
    end
  end

  describe '.unadvertised_mode' do
    it 'builds a -32602 error naming the mode the client lacks' do
      error = ACP::RequestError.unadvertised_mode('elicitation.form')

      assert_equal(
        [-32_602, 'Client does not advertise elicitation.form', nil],
        [error.code, error.message, error.data]
      )
    end
  end

  describe '.unadvertised_agent' do
    it 'builds a -32601 error naming the capability the agent lacks' do
      error = ACP::RequestError.unadvertised_agent('loadSession')

      assert_equal [-32_601, 'Agent does not advertise loadSession', nil], [error.code, error.message, error.data]
    end
  end

  describe '.internal_error' do
    it 'builds a -32603 error' do
      error = ACP::RequestError.internal_error

      assert_equal [-32_603, 'Internal error', nil], [error.code, error.message, error.data]
    end
  end

  describe '.invalid_response' do
    it 'builds a -32603 error carrying the malformed response as data' do
      error = ACP::RequestError.invalid_response({ 'sessionId' => 7 })

      assert_equal [-32_603, 'Invalid response', { 'sessionId' => 7 }], [error.code, error.message, error.data]
    end
  end

  describe '.unsupported_protocol_version' do
    it 'builds a -32603 error naming the requested and returned versions' do
      error = ACP::RequestError.unsupported_protocol_version(requested: 1, returned: 2)

      assert_equal(
        [-32_603, 'Unsupported protocol version: requested 1, returned 2', nil],
        [error.code, error.message, error.data]
      )
    end
  end

  describe '.request_cancelled' do
    it 'builds a -32800 error' do
      error = ACP::RequestError.request_cancelled

      assert_equal [-32_800, 'Request cancelled', nil], [error.code, error.message, error.data]
    end
  end

  describe '.auth_required' do
    it 'builds a -32000 error' do
      error = ACP::RequestError.auth_required

      assert_equal [-32_000, 'Authentication required', nil], [error.code, error.message, error.data]
    end
  end

  describe '.resource_not_found' do
    it 'builds a -32002 error without data when no uri is given' do
      error = ACP::RequestError.resource_not_found

      assert_equal [-32_002, 'Resource not found', nil], [error.code, error.message, error.data]
    end

    it 'carries the uri in data' do
      error = ACP::RequestError.resource_not_found('file:///a.txt')

      assert_equal [-32_002, 'Resource not found', { uri: 'file:///a.txt' }], [error.code, error.message, error.data]
    end
  end
end
