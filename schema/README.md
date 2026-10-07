# Vendored ACP schema

`schema.json` is the Agent Client Protocol v1 JSON Schema from the [Schema v1.24.1 release](https://github.com/agentclientprotocol/agent-client-protocol/releases/tag/schema-v1.24.1), unmodified. `bin/types` generates `lib/acp/types` from it.

`schema.unstable.json` is the same release's unstable schema, also unmodified. `bin/types` additionally generates the defs it adds or changes over the stable schema under `ACP::Types::Unstable`, which callers opt into with `require 'acp/types/unstable'`. Defs identical to a stable one are not duplicated; they resolve to the stable class. See the main README for the stability caveats.

To move to another release, replace the files and regenerate:

```sh
curl -fsSL -o schema/schema.json \
  https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/schema-v1.24.1/schema/v1/schema.json
curl -fsSL -o schema/schema.unstable.json \
  https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/schema-v1.24.1/schema/v1/schema.unstable.json
bin/types
```
