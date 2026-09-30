# acp-sdk

Ruby SDK for the Agent Client Protocol. The gem is `acp-sdk`; the namespace is `ACP`.

## Workflow

- Run every chore through its `bin/` script (`bin/test`, `bin/lint`, `bin/typecheck`, `bin/rbs`, `bin/ci`), never rake directly. Run `bin/ci` before pushing.
- After any `lib/` change, run `bin/rbs` and commit `sig/generated`. Never hand-edit `sig/generated`; `bin/typecheck` fails when it is stale.
- PR titles are Conventional Commits and become the squash commit on `main`: `feat:` releases a minor, `fix:` a patch. release-please owns `lib/acp/version.rb` and `CHANGELOG.md`; never edit them by hand.

## Code layout

- Zeitwerk loads `lib/acp` as the root of `ACP`, so `lib/acp/foo_bar.rb` defines `ACP::FooBar`.
- Tests are Minitest spec style (`describe`/`it`), and `test/acp/` mirrors `lib/acp/`.

## Comments

The default is no comment. Keep only a _why_ the code can't show (a non-local constraint, an external quirk, a deliberate tradeoff), at the line it explains. Never restate the code, repeat types the signatures state, or record history.

## Typing

- Steep runs `D::Ruby.all_error`: every diagnostic is an error. Fix the annotation or the code; never disable a diagnostic in the Steepfile. The only escape is a targeted inline suppression with a comment saying why.
- Annotate every method in `lib/` with rbs-inline doc style: one `# @rbs name: Type` per param plus `# @rbs return: Type`, never the one-line method-type form. Constants and `attr_reader`s rbs-inline can't infer take a trailing `#: Type` on the same line (0.14 ignores one on the line above).
- An `attr_reader`/`attr_writer` needs a `# @dynamic name` line directly above it, or Steep reports `MethodDefinitionMissing`.
- Value objects are frozen POROs, never `Data.define`/`Struct.new` (Steep can't see methods defined on the generated class), and never fixed-key hashes passed between methods. An RBS record type such as `{ cwd: String, history: Array[...] }`, inline or aliased, or a hash read back with `[:key]`/`fetch(:key)` elsewhere, is the tell. JSON-RPC payloads stay `Hash[String, untyped]` only at the wire boundary: the transport and the generated `from_h`/`to_h`.
- `sig/manual/` mirrors `lib/` for signatures rbs-inline can't generate, such as interfaces and `extend self` re-declarations (rbs-inline drops `extend self`). Namespace modules are defined in `lib/`, not declared in `sig/manual/`. `sig/_private/` holds stubs for dependencies with no RBS anywhere (e.g. `zeitwerk.rbs`); check gem_rbs_collection before writing one, and delete a stub once real signatures exist.
