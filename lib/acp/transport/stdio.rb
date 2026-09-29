# frozen_string_literal: true

require 'json'

# JSON-RPC 2.0 over newline-delimited JSON on an IO pair. A reader thread
# dispatches inbound messages while outbound requests are pending, and each
# inbound request is served on its own thread, so a handler can make an
# outbound request mid-turn and still see notifications (e.g. session/cancel)
# that arrive meanwhile.
class ACP::Transport::Stdio
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
  # @rbs notifications: Hash[String, _NotificationHandler]
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
  # @rbs return: ACP::Transport::Result
  def request(method, params = nil)
    queue = Thread::Queue.new
    id = register(queue)
    return ACP::Transport::Result.error(CONNECTION_CLOSED) unless id

    write({ 'jsonrpc' => '2.0', 'id' => id, 'method' => method, 'params' => params }.compact)
    queue.pop || ACP::Transport::Result.error(CONNECTION_CLOSED)
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
  # @rbs notifications: Hash[String, _NotificationHandler]
  # @rbs return: void
  def receive(line, requests, notifications)
    message = parse(line)
    case message
    when ACP::Transport::ResponseError then reply(nil, ACP::Transport::Result.error(message))
    else route(message, requests, notifications)
    end
  end

  # @rbs message: Hash[String, untyped]
  # @rbs requests: Hash[String, _Handler]
  # @rbs notifications: Hash[String, _NotificationHandler]
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
      quietly { handler.call(message['params']) } if handler
    elsif message.key?('result')
      settle(message['id'], ACP::Transport::Result.ok(message['result']))
    elsif error.is_a?(Hash) && error['code'].is_a?(Integer) && error['message'].is_a?(String)
      code, text, data = error.values_at('code', 'message', 'data')
      response_error = ACP::Transport::ResponseError.new(code:, message: text, data:)
      settle(message['id'], ACP::Transport::Result.error(response_error))
    else
      reply(nil, ACP::Transport::Result.error(INVALID_REQUEST))
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
      outcome = handler ? invoke(handler, params) : ACP::Transport::Result.error(METHOD_NOT_FOUND)
      case outcome
      when ACP::Transport::Reply
        reply(id, outcome.result)
        quietly(&outcome.after)
      else reply(id, outcome)
      end
    end
  end

  # For code with no reply to carry an error: a notification handler, or a
  # Reply's after once the reply is on the wire. An exception must not kill
  # the reader thread or print a thread report.
  #
  # @rbs &block: () -> void
  # @rbs return: void
  def quietly
    yield
  rescue StandardError
    nil
  end

  # Handlers are application code at the protocol boundary: an exception
  # becomes an error response instead of killing the thread serving it.
  #
  # @rbs handler: _Handler
  # @rbs params: untyped
  # @rbs return: ACP::Transport::Result | ACP::Transport::Reply
  def invoke(handler, params)
    handler.call(params)
  rescue StandardError => e
    ACP::Transport::Result.error(ACP::Transport::ResponseError.new(code: INTERNAL_ERROR, message: e.message))
  end

  # @rbs id: untyped
  # @rbs result: ACP::Transport::Result
  # @rbs return: void
  def reply(id, result)
    error = result.error
    write({ 'jsonrpc' => '2.0', 'id' => id }.merge(error ? { 'error' => error.to_h } : { 'result' => result.value }))
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
  # @rbs result: ACP::Transport::Result
  # @rbs return: void
  def settle(id, result)
    @lock.synchronize { @pending.delete(id) }&.push(result)
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
