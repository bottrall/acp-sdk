# acp-sdk

[![Gem Version](https://badge.fury.io/rb/acp-sdk.svg)](https://rubygems.org/gems/acp-sdk)
[![CI](https://github.com/bottrall/acp-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/bottrall/acp-sdk/actions/workflows/ci.yml)

A Ruby SDK for the [Agent Client Protocol](https://agentclientprotocol.com) (ACP), the protocol editors such as Zed and JetBrains use to talk to coding agents. Use it to:

- **Build an agent** that any ACP client can run.
- **Drive an agent** from Ruby, for an editor integration, a script or a test suite.

Every ACP message is a typed Ruby object, and the SDK takes care of the wire format, capability negotiation and cancellation. It speaks ACP protocol version 1.

## Installation

Requires Ruby 3.4 or later.

```sh
bundle add acp-sdk
```

```ruby
require 'acp/sdk'
```

## Building an agent

An agent is a plain Ruby object. `ACP::AgentConnection` calls its methods with typed requests and sends back what they return. The block receives a `client` handle for talking back to the editor.

```ruby
require 'acp/sdk'
require 'securerandom'

class MyAgent
  def initialize(client:)
    @client = client
  end

  def new_session(_request)
    ACP::Types::NewSessionResponse.new(session_id: SecureRandom.uuid)
  end

  def prompt(request)
    reply = ACP::Types::ContentBlock::Text.new(text: 'Hello from Ruby!')
    @client.update(request.session_id, ACP::Types::SessionUpdate::AgentMessageChunk.new(content: reply))
    ACP::Types::PromptResponse.new(stop_reason: ACP::Types::StopReason::END_TURN)
  end

  def cancel(_notification); end
end

ACP::AgentConnection.new(
  transport: ACP::Transport::Stdio.new(input: $stdin, output: $stdout),
  capabilities: ACP::Types::AgentCapabilities.new,
  agent_info: ACP::Types::Implementation.new(name: 'my-agent', version: '1.0.0')
) { |client| MyAgent.new(client:) }.start.join
```

Point your editor at that script and you have a working agent. For a fuller one that streams updates, asks permission, handles cancellation, uses files and terminals and persists sessions, see [`examples/echo_agent.rb`](https://github.com/bottrall/acp-sdk/blob/main/examples/echo_agent.rb).

### Agent methods

Each request method returns its response type, or an [`ACP::RequestError`](#errors) to reject the request.

| Method | Implement it when |
| --- | --- |
| `new_session`, `prompt`, `cancel` | Always |
| `load_session` | `capabilities` sets `load_session` |
| `list_sessions`, `resume_session`, `close_session`, `delete_session` | `capabilities.session_capabilities` sets `list`, `resume`, `close` or `delete` |
| `authenticate` | You pass `auth_methods:` |
| `logout` | `capabilities.auth` sets `logout` |
| `change_session_mode`, `change_session_config_option` | Your sessions offer modes or config options |
| `session_created(response)` | You want a hook after `session/new` is answered, e.g. to send available commands |

`start` raises `ArgumentError` if you advertise a capability without implementing its method. Requests for anything you don't advertise are rejected before they reach your agent.

### Calling the client

| `client.` | Does |
| --- | --- |
| `update(session_id, update)` | Streams a `SessionUpdate`: message chunks, tool calls, plans and so on |
| `available_commands(session_id, commands)` | Advertises slash commands |
| `request_permission(request)` | Asks the user to approve a tool call |
| `read_text_file`, `write_text_file` | Reads and writes files through the editor |
| `create_terminal`, `terminal_output`, `wait_for_terminal_exit`, `kill_terminal`, `release_terminal` | Runs commands in the editor. Release every terminal you create. |
| `create_elicitation`, `complete_elicitation` | Asks the user for structured input |
| `capabilities` | The client's `ClientCapabilities` (`nil` until the client connects) |

File, terminal and elicitation calls need the matching client capability. Without it they return an error without contacting the client, so check `client.capabilities` before offering a feature that depends on one.

### Cancellation

`cancel` must return quickly, so record the cancellation and return. Call `client.cancel_requests` to unblock anything your agent is waiting on (a permission prompt, a terminal), then have `prompt` return `StopReason::CANCELLED`. The SDK doesn't end the turn for you.

Inside a request handler, `client.cancelled?` tells you whether the client has cancelled that request. Return `ACP::RequestError.request_cancelled` to stop early.

### Shutting down

`start` returns a thread that finishes when the client disconnects. To wait for in-flight handlers before closing your IO, keep a reference to the transport and call `transport.drain` after joining that thread.

## Driving an agent

`ACP::AgentProcess.spawn` launches an agent as a child process and connects to it. The process is terminated when the block exits, even if the block raises.

```ruby
ACP::AgentProcess.spawn(
  'my-agent', '--flag',
  env: { 'API_KEY' => '...' },
  cwd: Dir.pwd,
  permission: ->(request) { ask_the_user(request) },
  updates: ->(notification) { show(notification) }
) do |connection|
  connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1))
  session = connection.new_session(ACP::Types::NewSessionRequest.new(cwd: Dir.pwd, mcp_servers: []))

  prompt = [ACP::Types::ContentBlock::Text.new(text: 'hello')]
  connection.prompt_session(ACP::Types::PromptRequest.new(session_id: session.session_id, prompt:)) do |update|
    print update.content.text if update.is_a?(ACP::Types::SessionUpdate::AgentMessageChunk)
  end
end
```

- Connection methods mirror the protocol: `new_session`, `prompt_session`, `cancel_session`, `set_session_mode` and so on. `connect` sends `initialize`, because Ruby reserves that name.
- `prompt_session` and `load_session` yield the session's updates as they arrive. Updates sent at other times go to `updates:`.
- Without a block, `spawn` returns the process and you call `terminate` yourself. Pass `stderr: :capture` to collect the agent's stderr on `process.stderr`.

### Serving files, terminals and elicitation

To let the agent use files, terminals or elicitation, build an `ACP::ClientConnection` with a handler object for each capability and advertise the capability when you connect:

```ruby
class Files
  def read_text_file(request)
    ACP::Types::ReadTextFileResponse.new(content: File.read(request.path))
  end

  def write_text_file(request)
    File.write(request.path, request.content)
    ACP::Types::WriteTextFileResponse.new
  end
end

connection = ACP::ClientConnection.build(
  transport: ACP::Transport::Stdio.new(input: agent_stdout, output: agent_stdin),
  permission: ->(request) { ask_the_user(request) },
  fs: Files.new
)
connection.start
connection.connect(
  ACP::Types::InitializeRequest.new(
    protocol_version: 1,
    client_capabilities: ACP::Types::ClientCapabilities.new(
      fs: ACP::Types::FileSystemCapabilities.new(read_text_file: true, write_text_file: true)
    )
  )
)
```

| Keyword | Methods | Capability |
| --- | --- | --- |
| `permission` | a callable | Always required |
| `fs` | `read_text_file`, `write_text_file` | `fs.read_text_file`, `fs.write_text_file` |
| `terminal` | `create_terminal`, `terminal_output`, `wait_for_terminal_exit`, `kill_terminal`, `release_terminal` | `terminal` |
| `elicitation` | `create_elicitation`, and optionally `complete_elicitation` for url mode | `elicitation.form` or `elicitation.url` |

A handler object needs only the methods of the capabilities you advertise. Each method returns the response type or an `ACP::RequestError`. `connect` raises `ArgumentError` if you advertise a capability whose method the handler doesn't define.

`permission` and the request methods each run on their own thread, so they can block while the user decides. `updates` and `complete_elicitation` must return quickly.

## Errors

`ACP::RequestError` is what you return to reject a request, and what you get back when the other side rejects yours. Errors are returned, never raised:

```ruby
session = connection.new_session(request)
if session.is_a?(ACP::RequestError)
  warn "#{session.code}: #{session.message}"
end
```

- Build standard errors with `ACP::RequestError.invalid_params`, `.method_not_found`, `.resource_not_found`, `.auth_required` or `.request_cancelled`, or custom ones with `ACP::RequestError.new(code:, message:, data:)`.
- If a handler raises, the other side only sees `Internal error`. The exception is logged rather than sent, so a message can't leak paths or secrets. Return a `RequestError` when the other side should see the reason.
- If the connection drops, pending and later requests return an error whose `connection_closed?` is true.

## Types

Every ACP message is a frozen value class under `ACP::Types`, built with snake_case keyword arguments and converted with `from_h` and `to_h`.

- Unions are namespaces of variant classes, such as `ContentBlock::Text` and `SessionUpdate::ToolCall`. Match on them with `is_a?` or `case`.
- String enums are modules of constants, such as `StopReason::END_TURN`, `ToolKind::EDIT` and `Role::USER`.

## Extensions

Custom methods outside the spec must start with `_`. Both connections accept `extension_requests:` and `extension_notifications:` hashes of handlers keyed by method name, and send their own with `ext_request` and `ext_notify`:

```ruby
ACP::AgentConnection.new(
  # ...
  extension_requests: { '_my_agent/ping' => ->(params) { { 'pong' => params } } }
)

connection.ext_request('_my_agent/ping', { 'hello' => 'world' }) # => { "pong" => { "hello" => "world" } }
```

## Unstable features

Draft protocol features, such as session forking, providers, usage reporting and plan and compaction updates, live under `ACP::Types::Unstable` and load only when you opt in:

```ruby
require 'acp/types/unstable'
```

Once loaded, the connections support `fork_session`, `list_providers`, `set_provider` and `disable_provider`. Unstable features aren't part of the spec yet. Peers may not support them, and they can change or disappear in any release.

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/bottrall/acp-sdk). See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and workflow. Everyone interacting in the project is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](LICENSE.txt).
