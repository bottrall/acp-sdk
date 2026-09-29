# acp-sdk

A standalone Ruby implementation of the [Agent Client Protocol](https://agentclientprotocol.com) (ACP): a server for exposing an agent to ACP clients such as Zed and JetBrains, and a client for driving ACP agents from Ruby.

Namespace `ACP`. MIT licensed.

## Status

Intent only. Nothing is published yet; the `acp-sdk` gem name is claimed at the first release.

This repo exists so that [riffer-rig](https://github.com/bottrall/riffer-rig) can depend on it for its `riffer acp` host. Scope for the first release: JSON-RPC over stdio, `mcpServers` and `available_commands` in, permission requests and filesystem methods out.

## Serving an agent

An agent is a plain Ruby object. `ACP::Server` answers `initialize` itself, turns each request into its generated `ACP::Types` object, calls the agent, and sends back what it returns. The factory block receives an `ACP::Server::Client` handle, which the agent keeps for sending session updates and asking permission. [`examples/echo_agent.rb`](examples/echo_agent.rb) is a complete agent; `ruby examples/echo_agent.rb` serves it on stdio.

```ruby
server = ACP::Server.new(
  transport: ACP::Transport::Stdio.new(input: $stdin, output: $stdout),
  capabilities: ACP::Types::AgentCapabilities.new(load_session: true),
  agent_info: ACP::Types::Implementation.new(name: 'my-agent', version: '1.0.0')
) { |client| MyAgent.new(client:) }
server.start.join
```

The agent's contract:

- It defines `new_session`, `prompt` and `cancel`. `load_session` and `list_sessions` are required only when `capabilities` advertises `load_session` or `session_capabilities.list`; `start` raises `ArgumentError` when one is advertised but missing, and a method that is not advertised is answered with `-32601`. `session_created`, if defined, runs right after the `session/new` reply is sent.
- Each request method returns its response type or an `ACP::Transport::ResponseError`, which is sent as the error reply. Params that do not match the schema are answered with `-32602` before the agent sees them.
- `cancel` runs on the transport's reader thread, so it must return quickly: set a flag and let the prompt notice it.
- After a cancel, the agent must itself end the turn with `stopReason: cancelled`. The server does not enforce it.
- `client.capabilities` is `nil` until the client sends `initialize`.

## Development

Every project chore is a script in `bin/`. The Rakefile behind them is an implementation detail; you never need to call rake directly.

| Script          | What it does                                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------- |
| `bin/setup`     | Install dependencies on a fresh checkout (gems + rbs collection)                               |
| `bin/test`      | Run the test suite. Pass files and/or Minitest flags: `bin/test test/foo_test.rb -n /pattern/` |
| `bin/lint`      | Run RuboCop. Arguments are forwarded, e.g. `bin/lint -a`                                       |
| `bin/typecheck` | Check `lib/acp/types`, the rbs collection lockfile and `sig/generated` are current, then type-check with Steep |
| `bin/rbs`       | Regenerate `sig/generated` from the inline annotations in `lib/`                               |
| `bin/types`     | Regenerate `lib/acp/types` from `schema/schema.json`, then `sig/generated`                     |
| `bin/rbs-watch` | Regenerate `sig/generated` whenever `lib/` changes                                             |
| `bin/ci`        | Run everything CI runs, serially. Use before pushing                                           |
| `bin/build`     | Build the gem into `pkg/`; the publish workflow runs this before `gem push`                    |

## Releasing

PR titles are [conventional commits](https://www.conventionalcommits.org/) and are linted in CI: `feat:` bumps the minor version, `fix:` bumps the patch, and `feat!:` marks a breaking change (also a minor bump while we are on 0.x). `chore:`, `docs:`, `ci:`, `refactor:` and `test:` never release. Squash-merging makes the title the commit on `main`.

[release-please](https://github.com/googleapis/release-please) keeps a release PR open that bumps `lib/acp/version.rb` and writes `CHANGELOG.md`. Merging that PR tags `vX.Y.Z`, creates the GitHub Release and publishes the gem to RubyGems.org through Trusted Publishing; nothing is pushed by hand. The first release is 0.1.0.

## Maintainer

- Jake Bottrall - https://github.com/bottrall
