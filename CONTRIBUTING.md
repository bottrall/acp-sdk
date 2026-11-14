# Contributing

## Development

Every project chore is a script in `bin/`. The Rakefile behind them is an implementation detail; you never need to call rake directly.

| Script                     | What it does                                                                                                                                                                                                                                   |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bin/setup`                | Install dependencies on a fresh checkout (gems + rbs collection)                                                                                                                                                                               |
| `bin/test [paths]`         | Run the test suite. Pass files and/or Minitest flags: `bin/test test/foo_test.rb -n /pattern/`                                                                                                                                                 |
| `bin/lint [--fix] [paths]` | Run RuboCop; `--fix` autocorrects what it safely can. Pass files to lint only those                                                                                                                                                            |
| `bin/typecheck`            | Check `lib/acp/types`, the rbs collection lockfile and `sig/generated` are current, then type-check with Steep                                                                                                                                 |
| `bin/generate [--watch]`   | Regenerate `lib/acp/types` from `schema/schema.json` and `schema/schema.unstable.json`, then `sig/generated` from the inline annotations in `lib/` and `codegen/`; `--watch` regenerates `sig/generated` whenever `lib/` or `codegen/` changes |
| `bin/build`                | Build the gem into `pkg/`; the publish workflow runs this before `gem push`                                                                                                                                                                    |
| `bin/check`                | `bin/lint --fix`, then `bin/typecheck`, then `bin/test`. Run it before calling a change done                                                                                                                                                   |
| `bin/ci`                   | Run exactly what CI runs, without fixing anything. Use before pushing                                                                                                                                                                          |

`ruby examples/echo_agent.rb` serves the example agent on stdio, which is handy for trying changes against a real ACP client.

## Releasing

PR titles are [conventional commits](https://www.conventionalcommits.org/) and are linted in CI: `feat:` bumps the minor version, `fix:` bumps the patch, and `feat!:` marks a breaking change (also a minor bump while we are on 0.x). `chore:`, `docs:`, `ci:`, `refactor:` and `test:` never release. Squash-merging makes the title the commit on `main`.

[release-please](https://github.com/googleapis/release-please) keeps a release PR open that bumps `lib/acp/version.rb` and writes `CHANGELOG.md`. Merging that PR tags `vX.Y.Z`, creates the GitHub Release and publishes the gem to RubyGems.org through Trusted Publishing; nothing is pushed by hand.
