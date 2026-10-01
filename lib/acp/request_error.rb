# frozen_string_literal: true

# Transport-agnostic names for the schema's ErrorCode, with factories matching
# the official SDKs' RequestError.*.
module ACP::RequestError
  PARSE_ERROR = -32_700 #: Integer
  INVALID_REQUEST = -32_600 #: Integer
  METHOD_NOT_FOUND = -32_601 #: Integer
  INVALID_PARAMS = -32_602 #: Integer
  INTERNAL_ERROR = -32_603 #: Integer
  REQUEST_CANCELLED = -32_800 #: Integer
  AUTH_REQUIRED = -32_000 #: Integer
  RESOURCE_NOT_FOUND = -32_002 #: Integer

  # @rbs return: ACP::Transport::ResponseError
  def self.parse_error
    build(PARSE_ERROR, 'Parse error')
  end

  # @rbs return: ACP::Transport::ResponseError
  def self.invalid_request
    build(INVALID_REQUEST, 'Invalid request')
  end

  # @rbs return: ACP::Transport::ResponseError
  def self.method_not_found
    build(METHOD_NOT_FOUND, 'Method not found')
  end

  # @rbs return: ACP::Transport::ResponseError
  def self.invalid_params
    build(INVALID_PARAMS, 'Invalid params')
  end

  # @rbs return: ACP::Transport::ResponseError
  def self.internal_error
    build(INTERNAL_ERROR, 'Internal error')
  end

  # @rbs return: ACP::Transport::ResponseError
  def self.request_cancelled
    build(REQUEST_CANCELLED, 'Request cancelled')
  end

  # @rbs return: ACP::Transport::ResponseError
  def self.auth_required
    build(AUTH_REQUIRED, 'Authentication required')
  end

  # @rbs uri: String?
  # @rbs return: ACP::Transport::ResponseError
  def self.resource_not_found(uri = nil)
    build(RESOURCE_NOT_FOUND, 'Resource not found', uri && { uri: uri })
  end

  # @rbs code: Integer
  # @rbs message: String
  # @rbs data: untyped
  # @rbs return: ACP::Transport::ResponseError
  def self.build(code, message, data = nil)
    ACP::Transport::ResponseError.new(code:, message:, data:)
  end
  private_class_method :build
end
