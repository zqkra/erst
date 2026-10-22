# Instructions for coding agents

Read before writing code, in this order: `docs/ARCHITECTURE.md`, `docs/HYGIENE.md`, and `docs/DESIGN.md` for UI work.

## Ground rules

- Work only inside the paths your task assigns to you. Other agents edit other paths at the same time. If you need a change outside your paths, stop and describe it in your report.
- Do not commit. The lead reviews the working tree and commits.
- English only. Never use the em dash character (U+2014) anywhere.
- Follow the public names in `docs/ARCHITECTURE.md` exactly. If a name or signature there is wrong, say so in your report instead of silently changing it.
- Before you report done, run the gates your task lists and paste their final output lines.

## Environment

- Rust: `export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"` (also done by `scripts/env.sh`).
- Swift: Command Line Tools only, no Xcode. `swift build` works; `swift test` does not. Build one target at a time: `cd app && swift build --target <Target>`.
- Network access is available for crates.io and Swift package resolution.

## Report format

1. What you built, as a list of files with one line each.
2. Gate output (last lines of each command).
3. Anything you could not do, and why.
4. Interface changes other modules need to know about.
