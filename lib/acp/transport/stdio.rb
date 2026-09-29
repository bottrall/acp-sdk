# frozen_string_literal: true

require 'json'

# JSON-RPC 2.0 over newline-delimited JSON on an IO pair. A reader thread
# dispatches inbound messages while outbound requests are pending, and each
# inbound request is served on its own thread, so a handler can make an
# outbound request mid-turn and still see notifications (e.g. session/cancel)
# that arrive meanwhile.
class ACP::Transport::Stdio
  # @rbs!
  #   type result = [:ok, untyped] | [:error, ACP::Transport::ResponseError]
  #
  #   interface _Reader
  #     def each_line: () { (String) -> void } -> untyped
  #   end
  #
  #   interface _Writer
  #     def write: (String) -> untyped
  #     def flush: () -> untyped
  #   end
  #
  #   interface _Handler
  #     def call: (untyped params) -> result
  #   end

  # @rbs @input: _Reader
  # @rbs @output: _Writer
  # @rbs @write_lock: Thread::Mutex
  # @rbs @lock: Thread::Mutex
  # @rbs @pending: Hash[untyped, Thread::Queue]
  # @rbs @next_id: Integer
  # @rbs @closed: bool

  INTERNAL_ERROR = -32_603 #: Integer
  PARSE_ERROR = ACP::Transport::ResponseError.new(code: -32_700, message: 'Parse error') #: ACP::Transport::ResponseError
  INVALID_REQUEST = ACP::Transport::ResponseError.new(code: -32_600, message: 'Invalid request') #: ACP::Transport::ResponseError
  METHOD_NOT_FOUND = ACP::Transport::ResponseError.new(code: -32_601, message: 'Method not found') #: ACP::Transport::ResponseError
  CONNECTION_CLOSED = ACP::Transport::ResponseError.new(code: INTERNAL_ERROR, message: 'Connection closed') #: ACP::Transport::ResponseError

  # @rbs input: _Reader
  # @rbs output: _Writer
  # @rbs return: void
  def initialize(input:, output:)
    @input = input
    @output = output
    @write_lock = Mutex.new
    @lock = Mutex.new
    @pending = {}
    @next_id = 0
    @closed = false
  end

  # Returns the reader thread, which ends at EOF on input after releasing any
  # pending outbound requests.
  #
  # @rbs requests: Hash[String, _Handler]
  # @rbs notifications: Hash[String, _Handler]
  # @rbs return: Thread
  def start(requests: {}, notifications: {})
    Thread.new do
      # Binary copy: String#strip raises on invalid UTF-8, which parse reports.
      @input.each_line { |line| receive(line, requests, notifications) unless line.b.strip.empty? }
    ensure
      close
    end
  end

  # @rbs method: String
  # @rbs params: untyped
  # @rbs return: result
  def request(method, params = nil)
    queue = Thread::Queue.new
    id = register(queue)
    return [:error, CONNECTION_CLOSED] unless id

    write({ 'jsonrpc' => '2.0', 'id' => id, 'method' => method, 'params' => params }.compact)
    queue.pop || [:error, CONNECTION_CLOSED]
  end

  # @rbs method: String
  # @rbs params: untyped
  # @rbs return: void
  def notify(method, params = nil)
    write({ 'jsonrpc' => '2.0', 'method' => method, 'params' => params }.compact)
  end

  private

  # @rbs line: String
  # @rbs requests: Hash[String, _Handler]
  # @rbs notifications: Hash[String, _Handler]
  # @rbs return: void
  def receive(line, requests, notifications)
    message = parse(line)
    case message
    when ACP::Transport::ResponseError then reply(nil, [:error, message])
    else route(message, requests, notifications)
    end
  end

  # @rbs message: Hash[String, untyped]
  # @rbs requests: Hash[String, _Handler]
  # @rbs notifications: Hash[String, _Handler]
  # @rbs return: void
  def route(message, requests, notifications)
    method = message['method']
    error = message['error']
    if method.is_a?(String) && message.key?('id')
      serve(requests[method], message['id'], message['params'])
    elsif method.is_a?(String)
      # Run on the reader thread so notifications (session/update) keep their
      # order; a JSON-RPC notification has no reply to carry a handler error.
      handler = notifications[method]
      invoke(handler, message['params']) if handler
    elsif message.key?('result')
      settle(message['id'], [:ok, message['result']])
    elsif error.is_a?(Hash) && error['code'].is_a?(Integer) && error['message'].is_a?(String)
      code, text, data = error.values_at('code', 'message', 'data')
      settle(message['id'], [:error, ACP::Transport::ResponseError.new(code:, message: text, data:)])
    else
      reply(nil, [:error, INVALID_REQUEST])
    end
  end

  # @rbs line: String
  # @rbs return: Hash[String, untyped] | ACP::Transport::ResponseError
  def parse(line)
    return PARSE_ERROR unless line.valid_encoding?

    message = JSON.parse(line)
    message.is_a?(Hash) ? message : INVALID_REQUEST
  rescue JSON::ParserError
    PARSE_ERROR
  end

  # @rbs handler: _Handler?
  # @rbs id: untyped
  # @rbs params: untyped
  # @rbs return: void
  def serve(handler, id, params)
    Thread.new do
      reply(id, handler ? invoke(handler, params) : [:error, METHOD_NOT_FOUND])
    end
  end

  # Handlers are application code at the protocol boundary: an exception
  # becomes an error response instead of killing the thread serving it.
  #
  # @rbs handler: _Handler
  # @rbs params: untyped
  # @rbs return: result
  def invoke(handler, params)
    handler.call(params)
  rescue StandardError => e
    [:error, ACP::Transport::ResponseError.new(code: INTERNAL_ERROR, message: e.message)]
  end

  # @rbs id: untyped
  # @rbs outcome: result
  # @rbs return: void
  def reply(id, outcome)
    status, value = outcome
    write({ 'jsonrpc' => '2.0', 'id' => id }.merge(status == :ok ? { 'result' => value } : { 'error' => value.to_h }))
  end

  # @rbs queue: Thread::Queue
  # @rbs return: Integer?
  def register(queue)
    @lock.synchronize do
      next if @closed

      id = @next_id += 1
      @pending[id] = queue
      id
    end
  end

  # @rbs id: untyped
  # @rbs outcome: result
  # @rbs return: void
  def settle(id, outcome)
    @lock.synchronize { @pending.delete(id) }&.push(outcome)
  end

  # @rbs return: void
  def close
    @lock.synchronize do
      @closed = true
      @pending.each_value(&:close)
      @pending.clear
    end
  end

  # @rbs message: Hash[String, untyped]
  # @rbs return: void
  def write(message)
    line = "#{JSON.generate(message)}\n"
    @write_lock.synchronize do
      @output.write(line)
      @output.flush
    end
  end
end
