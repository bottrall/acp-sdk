# Vendored ACP schema

`schema.json` is the Agent Client Protocol v1 JSON Schema from the [Schema v1.21.0 release](https://github.com/agentclientprotocol/agent-client-protocol/releases/tag/schema-v1.21.0), unmodified. `bin/types` generates `lib/acp/types` from it.

To move to another release, replace the file and regenerate:

```sh
curl -fsSL -o schema/schema.json \
  https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/schema-v1.21.0/schema/v1/schema.json
bin/types
```
