# frozen_string_literal: true

# The schema's JSON-RPC Error object, named after the official SDKs'
# RequestError: built by handlers and local refusals, and decoded from a
# peer's error replies by the transport.
class ACP::RequestError
  PARSE_ERROR = -32_700 #: Integer
  INVALID_REQUEST = -32_600 #: Integer
  METHOD_NOT_FOUND = -32_601 #: Integer
  INVALID_PARAMS = -32_602 #: Integer
  INTERNAL_ERROR = -32_603 #: Integer
  REQUEST_CANCELLED = -32_800 #: Integer
  AUTH_REQUIRED = -32_000 #: Integer
  RESOURCE_NOT_FOUND = -32_002 #: Integer

  # @rbs code: Integer
  # @rbs message: String
  # @rbs data: untyped
  # @rbs return: void
  def initialize(code:, message:, data: nil)
    @code = code
    @message = message
    @data = data
    freeze
  end

  # @dynamic code
  attr_reader :code #: Integer

  # @dynamic message
  attr_reader :message #: String

  # @dynamic data
  attr_reader :data #: untyped

  # @rbs return: Hash[String, untyped]
  def to_h
    { 'code' => code, 'message' => message, 'data' => data }.compact
  end

  # @rbs return: ACP::RequestError
  def self.parse_error
    new(code: PARSE_ERROR, message: 'Parse error')
  end

  # @rbs return: ACP::RequestError
  def self.invalid_request
    new(code: INVALID_REQUEST, message: 'Invalid request')
  end

  # @rbs method: String?
  # @rbs return: ACP::RequestError
  def self.method_not_found(method = nil)
    new(code: METHOD_NOT_FOUND, message: 'Method not found', data: method && { method: method })
  end

  # @rbs errors: Array[String]?
  # @rbs return: ACP::RequestError
  def self.invalid_params(errors = nil)
    new(code: INVALID_PARAMS, message: 'Invalid params', data: errors && { errors: errors })
  end

  # The method-not-found code for a method the client's capabilities do not
  # advertise, with a message that names the capability so it can be told
  # apart from an unknown method.
  #
  # @rbs capability: String
  # @rbs return: ACP::RequestError
  def self.unadvertised(capability)
    new(code: METHOD_NOT_FOUND, message: "Client does not advertise #{capability}")
  end

  # The invalid-params code for a request whose mode the client's
  # capabilities do not advertise, with a message that names the mode so it
  # can be told apart from malformed params. The spec gives elicitation a
  # mode in its params, so an unadvertised one is invalid params rather than
  # method not found.
  #
  # @rbs mode: String
  # @rbs return: ACP::RequestError
  def self.unadvertised_mode(mode)
    new(code: INVALID_PARAMS, message: "Client does not advertise #{mode}")
  end

  # @rbs return: ACP::RequestError
  def self.internal_error
    new(code: INTERNAL_ERROR, message: 'Internal error')
  end

  # The message tells a malformed peer reply apart from an internal error a
  # handler raised, though both use the -32603 code.
  #
  # @rbs response: untyped
  # @rbs return: ACP::RequestError
  def self.invalid_response(response)
    new(code: INTERNAL_ERROR, message: 'Invalid response', data: response)
  end

  # A local refusal of an initialize reply that names a version the SDK does
  # not speak; the message names both versions so logs can tell it from a
  # peer's error.
  #
  # @rbs requested: Integer
  # @rbs returned: Integer
  # @rbs return: ACP::RequestError
  def self.unsupported_protocol_version(requested:, returned:)
    new(code: INTERNAL_ERROR, message: "Unsupported protocol version: requested #{requested}, returned #{returned}")
  end

  # @rbs return: ACP::RequestError
  def self.request_cancelled
    new(code: REQUEST_CANCELLED, message: 'Request cancelled')
  end

  # @rbs return: ACP::RequestError
  def self.auth_required
    new(code: AUTH_REQUIRED, message: 'Authentication required')
  end

  # @rbs uri: String?
  # @rbs return: ACP::RequestError
  def self.resource_not_found(uri = nil)
    new(code: RESOURCE_NOT_FOUND, message: 'Resource not found', data: uri && { uri: uri })
  end
end
