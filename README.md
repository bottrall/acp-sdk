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

An agent is a plain Ruby object. `ACP::AgentConnection` answers `initialize` itself, turns each request into its generated `ACP::Types` object, calls the agent, and sends back what it returns. The factory block receives an `ACP::AgentConnection::Client` handle, which the agent keeps for sending session updates and asking permission.

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

- It defines `new_session`, `prompt` and `cancel`. `load_session` and `list_sessions` are required only when `capabilities` advertises `load_session` or `session_capabilities.list`; `start` raises `ArgumentError` when one is advertised but missing, and a method that is not advertised is answered with `-32601`. `session_created`, if defined, runs right after the `session/new` reply is sent.
- Each request method returns its response type or an `ACP::Transport::ResponseError`, which is sent as the error reply. Params that do not match the schema are answered with `-32602` before the agent sees them.
- `cancel` runs on the transport's reader thread, so it must return quickly: set a flag and let the prompt notice it.
- After a cancel, the agent must itself end the turn with `stopReason: cancelled`. `ACP::AgentConnection` does not enforce it.
- `client.capabilities` is `nil` until the client sends `initialize`.

[`examples/echo_agent.rb`](https://github.com/bottrall/acp-sdk/blob/main/examples/echo_agent.rb) is a complete agent that streams updates, asks permission, handles cancellation, and supports `session/load` and `session/list`.

## Driving an agent

`ACP::ClientConnection` is the other side of the same transport. Each method takes the request's generated `ACP::Types` object and returns its response type or the agent's `ACP::Transport::ResponseError`. `connect` sends `initialize`, since Ruby reserves that name for the constructor.

```ruby
require 'acp/sdk'
require 'open3'

stdin, stdout, = Open3.popen2('my-agent')
connection = ACP::ClientConnection.new(
  transport: ACP::Transport::Stdio.new(input: stdout, output: stdin),
  permission: ->(request) { ask_the_user(request) },
  updates: ->(notification) { show(notification) }
)
connection.start
connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1))
session = connection.session_new(ACP::Types::NewSessionRequest.new(cwd: Dir.pwd, mcp_servers: []))
prompt = [ACP::Types::ContentBlock::Text.new(text: 'hello')]
response = connection.session_prompt(ACP::Types::PromptRequest.new(session_id: session.session_id, prompt:)) do |update|
  print update.content.text if update.is_a?(ACP::Types::SessionUpdate::AgentMessageChunk)
end
```

- `session_prompt` and `session_load` yield the session's updates on the calling thread as they arrive and return once the agent replies. Updates outside those calls, such as the available commands after `session/new`, go to `updates`, which runs on the reader thread and must return quickly.
- `permission` answers `session/request_permission` with an `ACP::Types::RequestPermissionResponse` or an `ACP::Transport::ResponseError`. It runs on its own thread, so it may block while the user decides, and `session_cancel` can be sent meanwhile.

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/bottrall/acp-sdk). See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and workflow. Everyone interacting in the project is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](LICENSE.txt).
