# Contributing

## Development

Every project chore is a script in `bin/`. The Rakefile behind them is an implementation detail; you never need to call rake directly.

| Script          | What it does                                                                                                   |
| --------------- | -------------------------------------------------------------------------------------------------------------- |
| `bin/setup`     | Install dependencies on a fresh checkout (gems + rbs collection)                                               |
| `bin/test`      | Run the test suite. Pass files and/or Minitest flags: `bin/test test/foo_test.rb -n /pattern/`                 |
| `bin/lint`      | Run RuboCop. Arguments are forwarded, e.g. `bin/lint -a`                                                       |
| `bin/typecheck` | Check `lib/acp/types`, the rbs collection lockfile and `sig/generated` are current, then type-check with Steep |
| `bin/rbs`       | Regenerate `sig/generated` from the inline annotations in `lib/`                                               |
| `bin/types`     | Regenerate `lib/acp/types` from `schema/schema.json`, then `sig/generated`                                     |
| `bin/rbs-watch` | Regenerate `sig/generated` whenever `lib/` changes                                                             |
| `bin/ci`        | Run everything CI runs, serially. Use before pushing                                                           |
| `bin/build`     | Build the gem into `pkg/`; the publish workflow runs this before `gem push`                                    |

`ruby examples/echo_agent.rb` serves the example agent on stdio, which is handy for trying changes against a real ACP client.

## Releasing

PR titles are [conventional commits](https://www.conventionalcommits.org/) and are linted in CI: `feat:` bumps the minor version, `fix:` bumps the patch, and `feat!:` marks a breaking change (also a minor bump while we are on 0.x). `chore:`, `docs:`, `ci:`, `refactor:` and `test:` never release. Squash-merging makes the title the commit on `main`.

[release-please](https://github.com/googleapis/release-please) keeps a release PR open that bumps `lib/acp/version.rb` and writes `CHANGELOG.md`. Merging that PR tags `vX.Y.Z`, creates the GitHub Release and publishes the gem to RubyGems.org through Trusted Publishing; nothing is pushed by hand.
