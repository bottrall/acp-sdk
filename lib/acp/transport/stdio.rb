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
  # @rbs @serving: Hash[untyped, ACP::Transport::Cancellation]
  # @rbs @next_id: Integer
  # @rbs @closed: bool
  # @rbs @logger: ACP::Transport::_Logger

  CONNECTION_CLOSED = ACP::RequestError.new(
    code: ACP::RequestError::INTERNAL_ERROR, message: 'Connection closed'
  ) #: ACP::RequestError

  SERVING_CANCEL = :acp_serving_cancellation #: Symbol
  private_constant :SERVING_CANCEL

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
    @serving = {}
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

  # Cancels a pending outbound request: the peer is told $/cancel_request for
  # the request's id, and the waiting caller is released with -32800 only if
  # the peer answers that way, as the spec requires it to answer either way.
  # A cancel for an unknown or already-answered id is not sent.
  #
  # @rbs id: untyped
  # @rbs return: void
  def cancel(id)
    pending = @lock.synchronize { @pending.key?(id) }
    notify('$/cancel_request', { 'requestId' => id }) if pending
  end

  # The cancellation of the request the calling thread is serving, or nil off
  # a serve thread. A handler observes the peer's $/cancel_request through it
  # and can end early with ACP::RequestError.request_cancelled; whatever it
  # returns, the transport sends exactly one response.
  #
  # @rbs return: ACP::Transport::Cancellation?
  def cancellation
    Thread.current[SERVING_CANCEL] #: ACP::Transport::Cancellation?
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
    if method == '$/cancel_request' && !message.key?('id')
      # Cancellation is transport-owned: the notification targets a request
      # the transport is serving, not application state.
      cancel_request(message['params'])
    elsif method.is_a?(String) && message.key?('id')
      serve(requests[method], message['id'], message['params'], method)
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
      reply(detectable_id(message), ACP::RequestError.invalid_request)
    end
  end

  # JSON-RPC 2.0 says an error reply echoes the request id whenever it can be
  # detected; ids outside the spec's String/Number/Null types are not, so
  # those replies keep id null.
  #
  # @rbs message: Hash[String, untyped]
  # @rbs return: untyped
  def detectable_id(message)
    id = message['id']
    id.is_a?(String) || id.is_a?(Numeric) ? id : nil
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
  # @rbs method: String
  # @rbs return: void
  def serve(handler, id, params, method)
    cancellation = register_serving(id)
    Thread.new do
      Thread.current[SERVING_CANCEL] = cancellation
      outcome = handler ? invoke(handler, params) : ACP::RequestError.method_not_found(method)
      case outcome
      when ACP::Transport::Reply
        reply(id, outcome.result)
        quietly('reply after callback', &outcome.after)
      else reply(id, outcome)
      end
    ensure
      unregister_serving(id)
    end
  end

  # Registered before the serve thread starts so a cancel racing the request
  # cannot be missed, and dropped once the response is on the wire so later
  # cancels for the id are ignored.
  #
  # @rbs id: untyped
  # @rbs return: ACP::Transport::Cancellation
  def register_serving(id)
    cancellation = ACP::Transport::Cancellation.new
    @lock.synchronize { @serving[id] = cancellation }
    cancellation
  end

  # @rbs id: untyped
  # @rbs return: void
  def unregister_serving(id)
    @lock.synchronize { @serving.delete(id) }
  end

  # Marks the served request the notification targets, or ignores it when the
  # id is unknown or already answered. A notification has no reply to carry a
  # malformed params failure.
  #
  # @rbs params: untyped
  # @rbs return: void
  def cancel_request(params)
    id = params.is_a?(Hash) ? params['requestId'] : nil
    unless id.is_a?(String) || id.is_a?(Integer)
      return @logger.warn('dropped malformed $/cancel_request: missing requestId')
    end

    cancellation = @lock.synchronize { @serving[id] }
    cancellation&.cancel
  end

  # For code with no reply to carry an error: a notification handler, or a
  # Reply's after once the reply is on the wire. An exception must not kill
  # the reader thread or print a thread report.
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
  # becomes an error response instead of killing the thread serving it. The
  # exception is only logged, not sent: its message can carry paths, SQL or
  # anything else the handler interpolated, which must not reach the peer.
  #
  # @rbs handler: _Handler
  # @rbs params: untyped
  # @rbs return: (_ToH | ACP::RequestError | ACP::Transport::Reply)
  def invoke(handler, params)
    handler.call(params)
  rescue StandardError => e
    @logger.error("request handler raised #{e.class}: #{e.message}")
    ACP::RequestError.internal_error
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
