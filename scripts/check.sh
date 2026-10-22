#!/usr/bin/env bash
# The single quality gate: stop at the first failure and print PASS or FAIL per step.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$ERST_ROOT"

run_step() {
    label="$1"
    shift
    printf '==> %s\n' "$label"
    if "$@"; then
        printf 'PASS %s\n' "$label"
    else
        printf 'FAIL %s\n' "$label"
        exit 1
    fi
}

swift_target() {
    (cd "$ERST_ROOT/app" && ERST_CORE_PROFILE=debug swift build --target "$1")
}

run_step "scripts/hygiene.sh" "$ERST_ROOT/scripts/hygiene.sh"
run_step "cargo fmt --all --check" cargo fmt --all --check
run_step "cargo clippy --workspace --all-targets -- -D warnings" \
    cargo clippy --workspace --all-targets -- -D warnings
run_step "cargo test --workspace" cargo test --workspace
run_step "scripts/build-core.sh --debug" "$ERST_ROOT/scripts/build-core.sh" --debug

# Keep this list in sync with app/Package.swift.
for target in ErstCoreFFI ErstCore ErstModel ErstUI ErstKit ErstApp ErstPreview ErstSnapshots ErstProbe; do
    run_step "swift build --target $target (debug core)" swift_target "$target"
done

# ErstCore holds generated bindings, which use try! by design and are checked by scripts/build-core.sh.
run_step "swift format lint" \
    swift format lint --recursive --strict --configuration app/.swift-format \
    app/Sources/ErstApp \
    app/Sources/ErstKit \
    app/Sources/ErstModel \
    app/Sources/ErstPreview \
    app/Sources/ErstUI \
    app/Sources/ErstSnapshots \
    app/Sources/ErstProbe
