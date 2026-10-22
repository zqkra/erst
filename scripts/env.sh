#!/usr/bin/env bash
# Shared environment for every script: Rust toolchain on PATH and repo paths.
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:$PATH"
ERST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ERST_ROOT
