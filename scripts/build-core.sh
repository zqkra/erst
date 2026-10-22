#!/usr/bin/env bash
# Build the Rust core for macOS and regenerate the Swift bindings committed under app/.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$ERST_ROOT"

profile="release"
if [[ "${1:-}" == "--debug" ]]; then
    profile="debug"
elif [[ $# -gt 0 ]]; then
    printf 'usage: %s [--debug]\n' "$0" >&2
    exit 64
fi

target="aarch64-apple-darwin"
archive="$ERST_ROOT/target/$target/$profile/liberst_ffi.a"
swift_dir="$ERST_ROOT/app/Sources/ErstCore"
ffi_dir="$ERST_ROOT/app/Sources/ErstCoreFFI/include"
bindgen="$ERST_ROOT/target/debug/uniffi-bindgen"

printf '==> Building erst-ffi for %s (%s)\n' "$target" "$profile"
if [[ "$profile" == "debug" ]]; then
    cargo build --manifest-path "$ERST_ROOT/Cargo.toml" -p erst-ffi --target "$target"
else
    cargo build --manifest-path "$ERST_ROOT/Cargo.toml" -p erst-ffi --target "$target" --release
fi

if [[ ! -f "$archive" ]]; then
    printf 'error: expected static library at %s\n' "$archive" >&2
    exit 1
fi

printf '==> Building uniffi-bindgen\n'
cargo build --manifest-path "$ERST_ROOT/Cargo.toml" -p uniffi-bindgen

printf '==> Generating Swift bindings from %s\n' "$archive"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/erst-bindings.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
"$bindgen" generate --library "$archive" --language swift --out-dir "$tmp_dir" --no-format

for generated in erst_ffi.swift erst_ffiFFI.h erst_ffiFFI.modulemap; do
    if [[ ! -f "$tmp_dir/$generated" ]]; then
        printf 'error: bindgen did not produce %s\n' "$generated" >&2
        exit 1
    fi
done

normalize_em_dash() {
    # The UniFFI template writes U+2014 in one comment; docs/HYGIENE.md bans it, so replace it with ", " and trim the orphan space.
    LC_ALL=C awk -v dash=$'\xe2\x80\x94' '
        {
            if (index($0, dash)) {
                gsub(dash, ", ")
                gsub(/ ,/, ",")
                sub(/[ \t]+$/, "")
            }
            print
        }
    ' "$1" > "$1.normalized"
    mv "$1.normalized" "$1"
}

normalize_em_dash "$tmp_dir/erst_ffi.swift"
normalize_em_dash "$tmp_dir/erst_ffiFFI.h"

printf '==> Installing bindings into app/Sources\n'
mkdir -p "$swift_dir" "$ffi_dir"
install -m 644 "$tmp_dir/erst_ffi.swift" "$swift_dir/erst_ffi.swift"
install -m 644 "$tmp_dir/erst_ffiFFI.h" "$ffi_dir/erst_ffiFFI.h"
install -m 644 "$tmp_dir/erst_ffiFFI.modulemap" "$ffi_dir/module.modulemap"

printf 'Bindings ready (%s)\n' "$profile"
