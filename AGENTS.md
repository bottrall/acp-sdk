# acp-sdk

Ruby SDK for the Agent Client Protocol. The gem is `acp-sdk`; the namespace is `ACP`.

## Workflow

- Run every chore through its `bin/` script (`bin/test`, `bin/lint`, `bin/typecheck`, `bin/rbs`, `bin/ci`), never rake directly. Run `bin/ci` before pushing.
- After any `lib/` or `codegen/` change, run `bin/rbs` and commit `sig/generated`. Never hand-edit `sig/generated`; `bin/typecheck` fails when it is stale.
- PR titles are Conventional Commits and become the squash commit on `main`: `feat:` releases a minor, `fix:` a patch. release-please owns `lib/acp/version.rb` and `CHANGELOG.md`; never edit them by hand.

## Code layout

- Zeitwerk loads `lib/acp` as the root of `ACP`, so `lib/acp/foo_bar.rb` defines `ACP::FooBar`.
- Tests are Minitest spec style (`describe`/`it`), and `test/acp/` mirrors `lib/acp/`.

## Testing

- Every module of behaviour gets a test file, even if it's only a smoke test. A unit with no behaviour — pure constants, data definitions — needs no test file.
- Only test what can change. Static code — generated files, constants, trivial accessors — gets at most a smoke test. Generated code is pinned at its generator: test the generator, not each generated output.
- A test file tests only the concerns of the unit it's mapped to. If testing X requires driving Y's entry point, either the behaviour belongs in X's own file with collaborators injected, or Y's file is covering for a missing X test. A behaviour belongs to the unit whose contract it is, even when observing it means calling through an object that unit returns. A composer's tests assert the composer's outcomes only — never a collaborator's branches, which are pinned in the collaborator's own file.
- Order tests the way the code is ordered: they follow the source's structure, and within a routine they follow execution order (validation behaviour first).
- Test all branches in reason: every early return, conditional, and error path gets a test — unless the branch is dead or a programmer-error tripwire.

## Comments

The default is no comment. Keep only a _why_ the code can't show (a non-local constraint, an external quirk, a deliberate tradeoff), at the line it explains. Never restate the code, repeat types the signatures state, or record history.

## Typing

- Steep runs `D::Ruby.all_error`: every diagnostic is an error. Fix the annotation or the code; never disable a diagnostic in the Steepfile. The only escape is a targeted inline suppression with a comment saying why.
- Annotate every method in `lib/` and `codegen/` with rbs-inline doc style: one `# @rbs name: Type` per param plus `# @rbs return: Type`, never the one-line method-type form. Constants and `attr_reader`s rbs-inline can't infer take a trailing `#: Type` on the same line (0.14 ignores one on the line above).
- An `attr_reader`/`attr_writer` needs a `# @dynamic name` line directly above it, or Steep reports `MethodDefinitionMissing`.
- Value objects are frozen POROs, never `Data.define`/`Struct.new` (Steep can't see methods defined on the generated class), and never fixed-key hashes passed between methods. An RBS record type such as `{ cwd: String, history: Array[...] }`, inline or aliased, or a hash read back with `[:key]`/`fetch(:key)` elsewhere, is the tell. JSON-RPC payloads stay `Hash[String, untyped]` only at the wire boundary: the transport and the generated `from_h`/`to_h`.
- Declare an interface only when different objects satisfy it — two or more implementers, or a contract a consumer implements — or when a boundary forbids naming the one class. When only one class is ever passed, annotate that class; a test fake is not a second implementer.
- `sig/manual/` mirrors `lib/` (as `sig/manual/acp/`) and `codegen/` (as `sig/manual/codegen/`) for hand-written signatures: interfaces, type aliases and `extend self` re-declarations (rbs-inline drops `extend self`). Namespace modules are defined in `lib/`, not declared in `sig/manual/`. `sig/_private/` holds stubs for dependencies with no RBS anywhere (e.g. `zeitwerk.rbs`); check gem_rbs_collection before writing one, and delete a stub once real signatures exist.
