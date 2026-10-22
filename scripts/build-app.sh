#!/usr/bin/env bash
# Build and sign dist/Erst.app, including its command-line tool.
set -euo pipefail
# shellcheck source=scripts/env.sh
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
# Keep Rust's C dependencies at the app's minimum OS, even with a newer SDK.
export MACOSX_DEPLOYMENT_TARGET=26.0

target="aarch64-apple-darwin"
bundle="$ERST_ROOT/dist/Erst.app"

build_cli() {
    printf '==> Building erst-cli for %s (release)\n' "$target"
    cargo build --manifest-path "$ERST_ROOT/Cargo.toml" --release -p erst-cli --target "$target"
}

install_cli() {
    local contents="$1/Contents"
    # The usual case-insensitive APFS volume cannot put erst beside Erst.
    mkdir -p "$contents/Helpers"
    install -m 755 "$ERST_ROOT/target/$target/release/erst" "$contents/Helpers/erst"
}

build_swift() {
    export ERST_CORE_PROFILE=release
    "$ERST_ROOT/scripts/build-core.sh"

    printf '==> Building the Swift app (release)\n'
    # The native build system stamps the installed SDK into the binary. The default one stamps an
    # older SDK, and macOS then draws the app with the appearance of that older system.
    bin_dir="$(cd "$ERST_ROOT/app" && swift build -c release --product Erst --build-system native --show-bin-path)"
    # SwiftPM cannot see the Rust archive as a dependency, so force a new link.
    rm -f "$bin_dir/Erst"
    (cd "$ERST_ROOT/app" && swift build -c release --product Erst --build-system native)
}

install_metadata() {
    local contents="$1/Contents" version
    version="$(awk -F'"' '
        /^\[workspace\.package\]/ { in_section = 1; next }
        /^\[/ { in_section = 0 }
        in_section && /^version =/ { print $2; exit }
    ' "$ERST_ROOT/Cargo.toml")"
    if [[ -z "$version" ]]; then
        printf 'error: could not read the workspace version from Cargo.toml\n' >&2
        return 1
    fi
    install -m 644 "$ERST_ROOT/app/Support/Info.plist" "$contents/Info.plist"
    plutil -replace CFBundleShortVersionString -string "$version" "$contents/Info.plist"
    plutil -replace CFBundleVersion -string "$version" "$contents/Info.plist"
}

render_icon() {
    sips -z "$2" "$2" "$ERST_ROOT/brand/logo/icon-1024.png" --out "$3/$1" >/dev/null
}

install_icon() {
    local contents="$1/Contents" iconset="$ERST_ROOT/dist/Erst.iconset"
    printf '==> Generating the app icon\n'
    rm -rf "$iconset"
    mkdir -p "$iconset"
    render_icon icon_16x16.png 16 "$iconset"
    render_icon icon_16x16@2x.png 32 "$iconset"
    render_icon icon_32x32.png 32 "$iconset"
    render_icon icon_32x32@2x.png 64 "$iconset"
    render_icon icon_128x128.png 128 "$iconset"
    render_icon icon_128x128@2x.png 256 "$iconset"
    render_icon icon_256x256.png 256 "$iconset"
    render_icon icon_256x256@2x.png 512 "$iconset"
    render_icon icon_512x512.png 512 "$iconset"
    render_icon icon_512x512@2x.png 1024 "$iconset"
    iconutil -c icns "$iconset" -o "$contents/Resources/Erst.icns"
    rm -rf "$iconset"
}

assemble_bundle() {
    local contents="$1/Contents" resource_bundle
    printf '==> Assembling %s\n' "$1"
    rm -rf "$1"
    mkdir -p "$contents/MacOS" "$contents/Resources/Fonts"
    install -m 755 "$bin_dir/Erst" "$contents/MacOS/Erst"
    install_icon "$1"

    printf '==> Copying fonts\n'
    local font_source="$ERST_ROOT/app/Sources/ErstUI/Resources/Fonts"
    if [[ -d "$font_source" ]]; then
        find "$font_source" -maxdepth 1 -type f \
            \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.ttc' \) \
            -exec install -m 644 {} "$contents/Resources/Fonts/" \;
    fi

    printf '==> Copying SwiftPM resource bundles\n'
    for resource_bundle in "$bin_dir"/*.bundle; do
        [[ -d "$resource_bundle" ]] || continue
        cp -R "$resource_bundle" "$contents/Resources/"
    done

    # Connected agents link to this skill, so it updates with the app.
    printf '==> Copying the agent skill\n'
    mkdir -p "$contents/Resources/skill"
    cp -R "$ERST_ROOT/app/Support/skill/erst" "$contents/Resources/skill/"
}

sign_bundle() {
    local app_bundle="$1" identities identity
    local sign_args=(--force)
    # Omitting -v also finds the self-signed identity before it is trusted.
    identities="$(security find-identity -p codesigning 2>/dev/null || true)"
    identity="${ERST_SIGN_IDENTITY:-}"
    if [[ -z "$identity" ]]; then
        identity="$(awk '
            /"Erst Development"/ && length($2) == 40 && $2 !~ /[^[:xdigit:]]/ {
                print $2; exit
            }
        ' <<< "$identities")"
        if [[ -n "$identity" ]]; then
            printf '==> Signing with Erst Development (%s)\n' "$identity"
        else
            identity="-"
            printf '==> Signing ad-hoc\n'
        fi
    else
        printf '==> Signing with ERST_SIGN_IDENTITY: %s\n' "$identity"
    fi

    if [[ -n "${ERST_SIGN_IDENTITY:-}" && "$identity" != "-" ]] && awk -F'"' -v identity="$identity" '
        $2 ~ /^Developer ID Application:/ &&
            (index($2, identity) || index(tolower($1), tolower(identity))) { found = 1 }
        END { exit !found }
    ' <<< "$identities"; then
        sign_args+=(--options runtime --timestamp)
    fi
    sign_args+=(--sign "$identity")

    codesign "${sign_args[@]}" "$app_bundle/Contents/Helpers/erst"
    # No App Sandbox in 0.1: Accessibility reads other apps' window titles,
    # and agent configuration files are written in the user's home folder.
    codesign "${sign_args[@]}" --entitlements "$ERST_ROOT/app/Support/Erst.entitlements" "$app_bundle"
    codesign --verify --strict "$app_bundle/Contents/Helpers/erst"
    codesign --verify --strict "$app_bundle"
}

main() {
    local skip_swift=false
    if [[ $# == 1 && "$1" == "--skip-swift" ]]; then
        skip_swift=true
    elif [[ $# != 0 ]]; then
        printf 'usage: %s [--skip-swift]\n' "$0" >&2
        return 64
    fi
    cd "$ERST_ROOT"
    if [[ "$skip_swift" == true && ! -x "$bundle/Contents/MacOS/Erst" ]]; then
        printf 'error: --skip-swift requires an existing bundle at %s\n' "$bundle" >&2
        return 1
    fi

    build_cli
    if [[ "$skip_swift" == false ]]; then
        build_swift
        assemble_bundle "$bundle"
    fi
    install_metadata "$bundle"
    install_cli "$bundle"
    sign_bundle "$bundle"
    printf 'Bundle: %s (%s)\n' "$bundle" "$(du -sh "$bundle" | awk '{print $1}')"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
