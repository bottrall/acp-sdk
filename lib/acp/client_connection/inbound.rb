# frozen_string_literal: true

# Serves the requests and notifications the agent sends the client. The routes
# are registered at start, before connect records the advertisement, so each
# one answers its refusal until then.
class ACP::ClientConnection::Inbound
  # @rbs @fs: ACP::ClientConnection::_FileSystem?
  # @rbs @terminal: ACP::ClientConnection::_Terminal?
  # @rbs @elicitation: ACP::ClientConnection::_Elicitation?
  # @rbs @elicitations: ACP::ClientConnection::Elicitations
  # @rbs @mcp_message: (^(ACP::Types::Unstable::MessageMcpRequest) ->
  #   (ACP::Types::Unstable::MessageMcpResponse::t | ACP::RequestError))?
  # @rbs @extension_requests: Hash[String, ^(untyped) -> untyped]
  # @rbs @extension_notifications: Hash[String, ^(untyped) -> void]
  # @rbs @capabilities: ACP::Types::ClientCapabilities?

  FS_ROUTES = [
    Route.new(
      rpc_method: 'fs/read_text_file',
      type: ACP::Types::ReadTextFileRequest,
      handler_method: :read_text_file,
      path: %i[fs read_text_file],
      capability: 'fs.readTextFile'
    ),
    Route.new(
      rpc_method: 'fs/write_text_file',
      type: ACP::Types::WriteTextFileRequest,
      handler_method: :write_text_file,
      path: %i[fs write_text_file],
      capability: 'fs.writeTextFile'
    )
  ].freeze #: Array[ACP::ClientConnection::Inbound::Route]

  # The terminal capability is a single bool, so its five routes share one
  # gate. Their handlers may block for as long as the command runs, so the
  # transport must serve each request on its own thread for this not to hold
  # up others.
  TERMINAL_ROUTES = [
    Route.new(
      rpc_method: 'terminal/create',
      type: ACP::Types::CreateTerminalRequest,
      handler_method: :create_terminal,
      path: %i[terminal],
      capability: 'terminal'
    ),
    Route.new(
      rpc_method: 'terminal/output',
      type: ACP::Types::TerminalOutputRequest,
      handler_method: :terminal_output,
      path: %i[terminal],
      capability: 'terminal'
    ),
    Route.new(
      rpc_method: 'terminal/wait_for_exit',
      type: ACP::Types::WaitForTerminalExitRequest,
      handler_method: :wait_for_terminal_exit,
      path: %i[terminal],
      capability: 'terminal'
    ),
    Route.new(
      rpc_method: 'terminal/kill',
      type: ACP::Types::KillTerminalRequest,
      handler_method: :kill_terminal,
      path: %i[terminal],
      capability: 'terminal'
    ),
    Route.new(
      rpc_method: 'terminal/release',
      type: ACP::Types::ReleaseTerminalRequest,
      handler_method: :release_terminal,
      path: %i[terminal],
      capability: 'terminal'
    )
  ].freeze #: Array[ACP::ClientConnection::Inbound::Route]

  # @dynamic mcp_advertised=
  attr_writer :mcp_advertised #: bool

  # @rbs elicitations: ACP::ClientConnection::Elicitations
  # @rbs fs: ACP::ClientConnection::_FileSystem?
  # @rbs terminal: ACP::ClientConnection::_Terminal?
  # @rbs elicitation: ACP::ClientConnection::_Elicitation?
  # @rbs mcp_message: (^(ACP::Types::Unstable::MessageMcpRequest) ->
  #   (ACP::Types::Unstable::MessageMcpResponse::t | ACP::RequestError))?
  # @rbs extension_requests: Hash[String, ^(untyped) -> untyped]
  # @rbs extension_notifications: Hash[String, ^(untyped) -> void]
  # @rbs return: void
  def initialize(
    elicitations:,
    fs: nil, # rubocop:disable Naming/MethodParameterName -- named after ClientCapabilities#fs
    terminal: nil,
    elicitation: nil,
    mcp_message: nil,
    extension_requests: {},
    extension_notifications: {}
  )
    ACP::Extensions.validate_names(extension_requests.keys + extension_notifications.keys)
    @elicitations = elicitations
    @fs = fs
    @terminal = terminal
    @elicitation = elicitation
    @mcp_message = mcp_message
    @extension_requests = extension_requests
    @extension_notifications = extension_notifications
    @capabilities = nil
    @mcp_advertised = false
  end

  # @rbs return: Hash[String, ACP::Transport::Stdio::_Handler]
  def requests
    {
      **FS_ROUTES.to_h { |route| [route.rpc_method, serve(route, @fs)] },
      **TERMINAL_ROUTES.to_h { |route| [route.rpc_method, serve(route, @terminal)] },
      'elicitation/create' => method(:create_elicitation),
      **mcp_requests,
      **@extension_requests
    }
  end

  # @rbs return: Hash[String, ACP::Transport::Stdio::_NotificationHandler]
  def notifications
    { 'elicitation/complete' => @elicitations.method(:complete), **@extension_notifications }
  end

  # Refuses, before anything is recorded, a capability whose handler is
  # missing: the agent would otherwise call a method nothing serves.
  #
  # @rbs capabilities: ACP::Types::ClientCapabilities?
  # @rbs return: void
  def advertise(capabilities)
    check_served('fs methods', unserved(FS_ROUTES, @fs, capabilities))
    check_served('terminal methods', unserved(TERMINAL_ROUTES, @terminal, capabilities))
    check_served('elicitation modes', unserved_elicitation_modes(capabilities&.elicitation))
    @capabilities = capabilities
  end

  private

  # @rbs route: ACP::ClientConnection::Inbound::Route
  # @rbs handler: untyped
  # @rbs return: ^(untyped) -> untyped
  def serve(route, handler)
    lambda do |params|
      next ACP::RequestError.unadvertised(route.capability) unless ACP::Protocol.advertised?(@capabilities, route.path)

      # Safe: advertise refuses an advertised capability no handler serves.
      parsed(route.type, params) { |request| handler.public_send(route.handler_method, request) }
    end
  end

  # @rbs type: ACP::Transport::_Parser
  # @rbs params: untyped
  # @rbs &block: (untyped) -> untyped
  # @rbs return: untyped
  def parsed(type, params)
    request = ACP::Types.parse(type, params)
    request.is_a?(ACP::Types::ParseError) ? ACP::RequestError.invalid_params([request.message]) : yield(request)
  end

  # @rbs routes: Array[ACP::ClientConnection::Inbound::Route]
  # @rbs handler: untyped
  # @rbs capabilities: ACP::Types::ClientCapabilities?
  # @rbs return: Array[String]
  def unserved(routes, handler, capabilities)
    routes.filter_map do |route|
      next unless ACP::Protocol.advertised?(capabilities, route.path)

      route.handler_method.to_s unless handler.respond_to?(route.handler_method)
    end
  end

  # @rbs capabilities: ACP::Types::ElicitationCapabilities?
  # @rbs return: Array[String]
  def unserved_elicitation_modes(capabilities)
    return [] if @elicitation.respond_to?(:create_elicitation)

    { 'elicitation.form' => capabilities&.form, 'elicitation.url' => capabilities&.url }.select { |_, on| on }.keys
  end

  # @rbs what: String
  # @rbs unserved: Array[String]
  # @rbs return: void
  def check_served(what, unserved)
    return if unserved.empty?

    raise ArgumentError, "initialize advertises #{what} no handler serves: #{unserved.join(', ')}"
  end

  # The unstable types are referenced while the route is built, so it can only
  # be served when the caller opted in with `require 'acp/types/unstable'`. It
  # is registered only when a handler serves it: unlike the fs and terminal
  # gates, the mcp gate reads the agent's advertisement, so nothing forces an
  # advertised request to have a handler.
  #
  # @rbs return: Hash[String, ^(untyped) -> untyped]
  def mcp_requests
    handler = @mcp_message
    return {} unless handler && ACP::Types.unstable_enabled?

    route = lambda do |params|
      next ACP::RequestError.unadvertised_agent('mcpCapabilities.acp') unless @mcp_advertised

      parsed(ACP::Types::Unstable::MessageMcpRequest, params) { |request| handler.call(request) }
    end
    { 'mcp/message' => route }
  end

  # A request for an unadvertised mode answers -32602: the spec gives
  # elicitation its mode in the params.
  #
  # @rbs params: untyped
  # @rbs return: (ACP::Types::CreateElicitationResponse | ACP::RequestError)
  def create_elicitation(params)
    parsed(ACP::Types::CreateElicitationRequest, params) do |request|
      refusal = elicitation_refusal(request)
      next refusal if refusal

      mode = request.mode
      @elicitations.register(mode.elicitation_id) if mode.is_a?(ACP::Types::CreateElicitationRequest::Mode::Url)
      # Safe: advertise refuses an advertised mode no handler serves.
      handler = @elicitation #: ACP::ClientConnection::_Elicitation
      handler.create_elicitation(request)
    end
  end

  # @rbs request: ACP::Types::CreateElicitationRequest
  # @rbs return: ACP::RequestError?
  def elicitation_refusal(request)
    modes = @capabilities&.elicitation
    case request.mode
    when ACP::Types::CreateElicitationRequest::Mode::Form
      ACP::RequestError.unadvertised_mode('elicitation.form') unless modes&.form
    when ACP::Types::CreateElicitationRequest::Mode::Url
      ACP::RequestError.unadvertised_mode('elicitation.url') unless modes&.url
    else
      ACP::RequestError.unadvertised_mode("elicitation.#{request.mode['mode']}")
    end
  end
end
