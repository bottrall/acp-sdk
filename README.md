# acp-sdk

A standalone Ruby implementation of the [Agent Client Protocol](https://agentclientprotocol.com) (ACP): a server for exposing an agent to ACP clients such as Zed and JetBrains, and a client for driving ACP agents from Ruby.

Namespace `ACP`. MIT licensed.

## Status

Intent only. Nothing is published yet; the `acp-sdk` gem name is claimed at the first release.

This repo exists so that [riffer-rig](https://github.com/bottrall/riffer-rig) can depend on it for its `riffer acp` host. Scope for the first release: JSON-RPC over stdio, `mcpServers` and `available_commands` in, permission requests and filesystem methods out.

## Maintainer

- Jake Bottrall - https://github.com/bottrall
