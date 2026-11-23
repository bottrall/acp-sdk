# Vendored ACP schema

`VERSION` names the [Agent Client Protocol schema release](https://github.com/agentclientprotocol/agent-client-protocol/releases) vendored here, and every file beside it comes from that release's `schema/v1/`, unmodified.

`schema.json` is the Agent Client Protocol v1 JSON Schema. `bin/generate` generates `lib/acp/types` from it.

`schema.unstable.json` is the same release's unstable schema. `bin/generate` additionally generates the defs it adds or changes over the stable schema under `ACP::Types::Unstable`, which callers opt into with `require 'acp/types/unstable'`. Defs identical to a stable one are not duplicated; they resolve to the stable class. See the main README for the stability caveats.

`meta.json` and `meta.unstable.json` are the spec's lists of the methods each side handles. The connection tests fail when they list a method the SDK neither routes nor lists as unsupported in that test file, and `test/schema/meta_test.rb` fails when they list a protocol method other than `$/cancel_request`, or a section none of these tests covers.

To move to another release, set `VERSION`, then fetch the files and regenerate:

```sh
bin/fetch-schema
bin/generate
```

When a new 1.x release is out, Renovate opens a `feat:` pull request with `VERSION` set and the files fetched. Neither Renovate nor the [deps fixer](https://github.com/bottrall/deps) merges it: the rule in `renovate.json` turns automerge off and labels it `deps-review`. Renovate doesn't regenerate. When that leaves CI red, the fixer runs `bin/generate`, then its agent, and pushes the regenerated files and whatever the agent changed as a commit per attempt, up to two, so review those commits as code. If it labels the pull request `needs-human` without having pushed the regenerated files, run `bin/generate` on the branch and commit the result.

`bin/diff-schema <before>` prints, as Markdown, the methods, defs and "MUST only send"-style rules that changed from the schema directory `before` to this one. The `schema-diff` workflow writes it to the job summary of every pull request that changes `schema/`.
