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
  # @rbs @logger: ACP::Transport::_Logger

  CONNECTION_CLOSED = ACP::RequestError.new(
    code: ACP::RequestError::INTERNAL_ERROR, message: 'Connection closed'
  ) #: ACP::RequestError

  # @rbs input: _Reader
  # @rbs output: _Writer
  # @rbs logger: ACP::Transport::_Logger
  # @rbs return: void
  def initialize(input:, output:, logger: ACP::Transport::StderrLogger.new)
    @input = input
    @output = output
    @write_lock = Mutex.new
    @lock = Mutex.new
    @pending = {}
    @next_id = 0
    @closed = false
    @logger = logger
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
  # @rbs return: (Hash[String, untyped] | ACP::RequestError)
  def request(method, params = nil)
    queue = Thread::Queue.new
    id = register(queue)
    return CONNECTION_CLOSED unless id

    write({ 'jsonrpc' => '2.0', 'id' => id, 'method' => method, 'params' => params }.compact)
    queue.pop || CONNECTION_CLOSED
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
    when ACP::RequestError then reply(nil, message)
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
      quietly('notification handler') { handler.call(message['params']) } if handler
    elsif message.key?('result')
      settle(message['id'], message['result'])
    elsif error.is_a?(Hash) && error['code'].is_a?(Integer) && error['message'].is_a?(String)
      code, text, data = error.values_at('code', 'message', 'data')
      settle(message['id'], ACP::RequestError.new(code:, message: text, data:))
    else
      reply(nil, ACP::RequestError.invalid_request)
    end
  end

  # @rbs line: String
  # @rbs return: Hash[String, untyped] | ACP::RequestError
  def parse(line)
    return ACP::RequestError.parse_error unless line.valid_encoding?

    message = JSON.parse(line)
    message.is_a?(Hash) ? message : ACP::RequestError.invalid_request
  rescue JSON::ParserError
    ACP::RequestError.parse_error
  end

  # @rbs handler: _Handler?
  # @rbs id: untyped
  # @rbs params: untyped
  # @rbs return: void
  def serve(handler, id, params)
    Thread.new do
      outcome = handler ? invoke(handler, params) : ACP::RequestError.method_not_found
      case outcome
      when ACP::Transport::Reply
        reply(id, outcome.result)
        quietly('reply after callback', &outcome.after)
      else reply(id, outcome)
      end
    end
  end

  # For code with no reply to carry an error: a notification handler, or a
  # Reply's after once the reply is on the wire. An exception must not kill
  # the reader thread or print a thread report; it is logged instead.
  #
  # @rbs label: String
  # @rbs &block: () -> void
  # @rbs return: void
  def quietly(label)
    yield
  rescue StandardError => e
    @logger.error("#{label} raised #{e.class}: #{e.message}")
  end

  # Handlers are application code at the protocol boundary: an exception
  # becomes an error response instead of killing the thread serving it.
  #
  # @rbs handler: _Handler
  # @rbs params: untyped
  # @rbs return: (_ToH | ACP::RequestError | ACP::Transport::Reply)
  def invoke(handler, params)
    handler.call(params)
  rescue StandardError => e
    ACP::RequestError.new(code: ACP::RequestError::INTERNAL_ERROR, message: e.message)
  end

  # The success arm is whatever the handler returned, which the transport only
  # knows serializes with to_h; RequestError picks the error arm of the reply.
  #
  # @rbs id: untyped
  # @rbs outcome: (_ToH | ACP::RequestError)
  # @rbs return: void
  def reply(id, outcome)
    payload = case outcome
              when ACP::RequestError then { 'error' => outcome.to_h }
              else { 'result' => outcome.to_h }
              end
    write({ 'jsonrpc' => '2.0', 'id' => id }.merge(payload))
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
  # @rbs result: (Hash[String, untyped] | ACP::RequestError)
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

  # A closed peer must not kill the thread writing the reply: the reader has
  # to keep draining input so pending requests still settle at EOF.
  #
  # @rbs message: Hash[String, untyped]
  # @rbs return: void
  def write(message)
    line = "#{JSON.generate(message)}\n"
    @write_lock.synchronize do
      @output.write(line)
      @output.flush
    end
  rescue Errno::EPIPE => e
    @logger.warn("write to closed peer: #{e.class}: #{e.message}")
  end
end
