# Contributing

Thanks for helping. Read these first:

1. `docs/ARCHITECTURE.md`: modules, contracts, and data flow.
2. `docs/HYGIENE.md`: the rules every change follows.
3. `docs/DESIGN.md`: tokens and screens, for UI work.

## Setup

- macOS 26 or later on Apple Silicon.
- Swift 6.2 or later. Command Line Tools are enough, and Xcode is optional.
- Rust stable, installed with rustup.

## Build and check

Run these from the repository root:

```sh
scripts/dev-identity.sh   # once per machine: creates the signing identity
scripts/check.sh          # format, lint, Rust tests, and a build of every target
scripts/build-app.sh      # builds dist/Erst.app without opening it
scripts/run.sh            # opens Erst with .erst-dev data and streams its log
```

- `scripts/check.sh` runs `scripts/hygiene.sh`, `cargo fmt --check`, clippy with `-D warnings`, `cargo test`, a debug core build, a Swift build of every target, and `swift format lint`. A change is done when it passes and you exercised the behavior the change adds.
- `scripts/build-app.sh --skip-swift` reuses an existing bundle and refreshes its helper and signatures.
- After you change `erst-ffi`, run `scripts/build-core.sh`. It regenerates the Swift bindings. Do not edit those generated files by hand.
- `swift test` needs Xcode. Put logic that needs tests in Rust, and keep the Swift code thin around Apple APIs.
- For UI changes, run `cd app && swift run ErstSnapshots`. It writes 2x PNGs of every screen and state to `.erst-dev/snapshots/`. Include the ones your change affects.

## Rules

- Read `docs/HYGIENE.md` before you write code. It covers names, file size, comments, Rust and Swift rules, design rules, tests, performance budgets, and commit messages.
- Coding agents read `AGENTS.md` first. It sets their working rules, such as staying inside the assigned paths and leaving commits to the maintainer. `CLAUDE.md` is a symlink to the same file.

## Pull requests

- Keep each pull request to one logical change, with `scripts/check.sh` passing.
- Write an imperative subject under 72 characters. Explain why in the body when it is not obvious.
- Do not add `Co-Authored-By` or "Generated with" trailers.
- Describe what changed and why. Include a screenshot for UI changes.
- Erst is dual licensed (AGPL-3.0 and a commercial license). Before your first contribution is merged you sign the Contributor License Agreement, which lets the project keep offering both licenses. You keep the copyright to your work.
