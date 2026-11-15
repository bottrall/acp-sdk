# Contributing

[`AGENTS.md`](AGENTS.md) holds the conventions for the code, for people and agents alike. By taking part you agree to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Setup

You need the Ruby in `.ruby-version` and the Node in `.nvmrc` (with pnpm through `corepack enable`), for whichever of the two the repo has. Then, on a fresh checkout:

```sh
bin/setup
```

## Day to day

Everything runs through `bin/`, never a tool directly.

| Script                        | Does                                                                                         |
| ----------------------------- | -------------------------------------------------------------------------------------------- |
| `bin/setup`                   | installs dependencies on a fresh checkout                                                    |
| `bin/test [paths]`            | runs the tests; pass files to run only those                                                 |
| `bin/lint [--fix] [paths]`    | checks lint and formatting; `--fix` fixes what it can                                        |
| `bin/typecheck`               | type-checks the code                                                                         |
| `bin/generate [--watch]`      | regenerates the generated files; `--watch` keeps them current                                |
| `bin/build`                   | builds what the repo ships                                                                   |
| `bin/check`                   | `bin/lint --fix`, then `bin/typecheck`, then `bin/test`: run it before calling a change done |
| `bin/ci`                      | runs exactly what CI runs, without fixing anything: run it before you push                   |

In a repo with both Ruby and TypeScript, each script runs the Ruby side then the TypeScript side; `--only=ruby` or `--only=ts` picks one.

## Pull requests

PR titles are [Conventional Commits](https://www.conventionalcommits.org/) (`feat: add X`, `fix: handle Y`), because each becomes the squash commit on `main` and the changelog is built from them; CI checks the title. `feat:` releases a minor version and `fix:` a patch. Fill in the PR template: the problem, the solution, and the proof that it works.

## Releasing

If the repo publishes releases (it has a `release-please-config.json`), they go through [release-please](https://github.com/googleapis/release-please). Every push to `main` updates its release PR, which bumps the version and writes the changelog section; merging that PR tags the release and publishes it. Never edit the version or `CHANGELOG.md` by hand.
