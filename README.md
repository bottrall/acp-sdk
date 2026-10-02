# acp-sdk

[![Gem Version](https://badge.fury.io/rb/acp-sdk.svg)](https://rubygems.org/gems/acp-sdk)

A Ruby SDK for the [Agent Client Protocol](https://agentclientprotocol.com) (ACP). It covers both sides of the protocol:

- **Agent side** (`ACP::AgentConnection`): expose your agent to ACP clients such as Zed and JetBrains.
- **Client side** (`ACP::ClientConnection`): drive ACP agents from Ruby, for an editor integration or for tests.

Every ACP request, response and notification is a generated Ruby class under `ACP::Types`, and messages travel as JSON-RPC over stdio. The SDK speaks ACP protocol version 1.

## Installation

Requires Ruby 4.0 or later.

Add the gem to your Gemfile:

```sh
bundle add acp-sdk
```

Or install it directly:

```sh
gem install acp-sdk
```

Then require it:

```ruby
require 'acp/sdk'
```

## Serving an agent

An agent is a plain Ruby object. `ACP::AgentConnection` answers `initialize` itself, turns each request into its generated `ACP::Types` object, calls the agent, and sends back what it returns. The factory block receives an `ACP::AgentConnection::Client` handle, which the agent keeps for sending session updates, asking permission, reading and writing files, and running commands in terminals.

```ruby
require 'acp/sdk'

connection = ACP::AgentConnection.new(
  transport: ACP::Transport::Stdio.new(input: $stdin, output: $stdout),
  capabilities: ACP::Types::AgentCapabilities.new(load_session: true),
  agent_info: ACP::Types::Implementation.new(name: 'my-agent', version: '1.0.0')
) { |client| MyAgent.new(client:) }
connection.start.join
```

The agent's contract:

- It defines `new_session`, `prompt` and `cancel`. `load_session`, `list_sessions`, `resume_session`, `close_session` and `delete_session` are required only when `capabilities` advertises `load_session` or `session_capabilities.list`, `.resume`, `.close` or `.delete`, and `authenticate` only when `auth_methods` is non-empty, and `logout` only when `capabilities` advertises `auth.logout`; `start` raises `ArgumentError` when one is advertised but missing, and a method that is not advertised is answered with `-32601`. `change_session_mode` and `change_session_config_option` are optional, since modes and config options are offered per session rather than in `initialize`; `session/set_mode` and `session/set_config_option` are answered with `-32601` when the agent does not define them. `session_created`, if defined, runs right after the `session/new` reply is sent.
- Each request method returns its response type or an `ACP::RequestError`, which is sent as the error reply. Params that do not match the schema are answered with `-32602` before the agent sees them.
- `cancel` runs on the transport's reader thread, so it must return quickly: set a flag and let the prompt notice it.
- After a cancel, the agent must itself end the turn with `stopReason: cancelled`. `ACP::AgentConnection` does not enforce it.
- `client.capabilities` is `nil` until the client sends `initialize`.
- `client.read_text_file` and `client.write_text_file` take an `ACP::Types::ReadTextFileRequest` or `ACP::Types::WriteTextFileRequest` and return the response type or an `ACP::RequestError`. Unless `client.capabilities` advertises `fs.read_text_file` or `fs.write_text_file`, they return `-32601` without sending anything to the client.
- `client.create_terminal`, `client.terminal_output`, `client.wait_for_terminal_exit`, `client.kill_terminal` and `client.release_terminal` take the matching `ACP::Types` request (`CreateTerminalRequest`, `TerminalOutputRequest`, `WaitForTerminalExitRequest`, `KillTerminalRequest`, `ReleaseTerminalRequest`) and return its response type or an `ACP::RequestError`. Unless `client.capabilities` advertises `terminal`, they return `-32601` without sending anything to the client. The agent must release every terminal it creates.

[`examples/echo_agent.rb`](https://github.com/bottrall/acp-sdk/blob/main/examples/echo_agent.rb) is a complete agent that streams updates, asks permission, handles cancellation, reads and writes files and runs commands through the client (`/read <path>`, `/write <path> <text>` and `/run <command> [args]`, each advertised as a slash command only when the client supports it), and supports `session/load` and `session/list`.

## Driving an agent

`ACP::ClientConnection` is the other side of the same transport. Each method takes the request's generated `ACP::Types` object and returns its response type or the agent's `ACP::RequestError`. `connect` sends `initialize`, since Ruby reserves that name for the constructor.

`ACP::AgentProcess.spawn` starts a command with args, env and cwd, wires its stdio to a new `ACP::ClientConnection` and starts it. The block receives the connection and the process handle (`pid`, plus `stderr` when captured), and the child is terminated — after its stdin is closed, with TERM and then KILL if it will not exit — when the block exits, so a raised block cannot leak the process. Without a block, `spawn` returns the process and calling `terminate` is yours. `stderr` is `:inherit` by default, so the child writes to your stderr; pass `:capture` to collect it on the process instead.

```ruby
require 'acp/sdk'

response = ACP::AgentProcess.spawn(
  'my-agent', '--flag',
  env: { 'API_KEY' => '...' },
  cwd: Dir.pwd,
  stderr: :capture,
  permission: ->(request) { ask_the_user(request) },
  updates: ->(notification) { show(notification) }
) do |connection|
  connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1))
  session = connection.session_new(ACP::Types::NewSessionRequest.new(cwd: Dir.pwd, mcp_servers: []))
  prompt = [ACP::Types::ContentBlock::Text.new(text: 'hello')]
  connection.session_prompt(ACP::Types::PromptRequest.new(session_id: session.session_id, prompt:)) do |update|
    print update.content.text if update.is_a?(ACP::Types::SessionUpdate::AgentMessageChunk)
  end
end
```

Any transport over a pair of IOs works too, so the connection can still be wired by hand when the agent is not a child process:

```ruby
connection = ACP::ClientConnection.new(
  transport: ACP::Transport::Stdio.new(input: some_io, output: other_io),
  permission: ->(request) { ask_the_user(request) },
  updates: ->(notification) { show(notification) }
)
```

- `session_prompt` and `session_load` yield the session's updates on the calling thread as they arrive and return once the agent replies. Updates outside those calls, such as the available commands after `session/new`, go to `updates`, which runs on the reader thread and must return quickly.
- `permission` answers `session/request_permission` with an `ACP::Types::RequestPermissionResponse` or an `ACP::RequestError`. It runs on its own thread, so it may block while the user decides, and `session_cancel` can be sent meanwhile.

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/bottrall/acp-sdk). See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and workflow. Everyone interacting in the project is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](LICENSE.txt).
