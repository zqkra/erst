#!/usr/bin/env bash
# Build, sign, notarize, and publish one release of Erst, with the feed the in-app updater reads.
#
#   scripts/release.sh NOTES_FILE            publish the version in Cargo.toml on GitHub Releases
#   scripts/release.sh --local NOTES_FILE    build the archive and feed in dist/release, publish nothing
#
# NOTES_FILE holds what changed, one sentence per line. Settings, About shows these lines.
# A real release needs ERST_SIGN_IDENTITY (a Developer ID Application identity) and
# ERST_NOTARY_PROFILE (a notarytool keychain profile). docs/RELEASING.md has the setup.
set -euo pipefail
# shellcheck source=scripts/env.sh
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

repository="zqkra/erst"
sparkle_account="erst"
release_dir="$ERST_ROOT/dist/release"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

workspace_version() {
    awk -F'"' '
        /^\[workspace\.package\]/ { in_section = 1; next }
        /^\[/ { in_section = 0 }
        in_section && /^version =/ { print $2; exit }
    ' "$ERST_ROOT/Cargo.toml"
}

check_publishable() {
    local version="$1"
    [[ -z "$(git -C "$ERST_ROOT" status --porcelain)" ]] || fail "commit or stash your changes first"
    [[ "$(git -C "$ERST_ROOT" branch --show-current)" == "main" ]] || fail "release from main"
    git -C "$ERST_ROOT" fetch --quiet origin main
    [[ "$(git -C "$ERST_ROOT" rev-parse HEAD)" == "$(git -C "$ERST_ROOT" rev-parse origin/main)" ]] ||
        fail "push main first, so the tag points at what you built"
    if gh release view "v$version" --repo "$repository" >/dev/null 2>&1; then
        fail "v$version is already released; raise the version in Cargo.toml"
    fi
    [[ "${ERST_SIGN_IDENTITY:-}" == Developer\ ID\ Application:* ]] ||
        fail "set ERST_SIGN_IDENTITY to your Developer ID Application identity"
    [[ -n "${ERST_NOTARY_PROFILE:-}" ]] || fail "set ERST_NOTARY_PROFILE to your notarytool profile"
}

notarize() {
    local dmg="$1"
    printf '==> Notarizing %s\n' "${dmg#"$ERST_ROOT"/}"
    xcrun notarytool submit "$dmg" --keychain-profile "$ERST_NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose "$dmg"
}

# Writes the feed with one item: the release just built. Sparkle compares sparkle:version with the
# installed CFBundleVersion, which build-app.sh sets to the same version.
write_appcast() {
    local version="$1" notes_file="$2" dmg="$3" base_url="$4" signature
    signature="$("$ERST_ROOT/app/.build/artifacts/sparkle/Sparkle/bin/sign_update" \
        --account "$sparkle_account" "$dmg")"
    [[ "$signature" == *edSignature=* ]] || fail "sign_update returned no signature: $signature"
    if grep -q ']]>' "$notes_file"; then
        fail "the notes cannot contain ]]>"
    fi
    {
        printf '<?xml version="1.0" encoding="utf-8"?>\n'
        printf '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">\n'
        printf '  <channel>\n    <title>Erst</title>\n    <item>\n'
        printf '      <title>Erst %s</title>\n' "$version"
        printf '      <pubDate>%s</pubDate>\n' "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
        printf '      <sparkle:version>%s</sparkle:version>\n' "$version"
        printf '      <sparkle:shortVersionString>%s</sparkle:shortVersionString>\n' "$version"
        printf '      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>\n'
        printf '      <description sparkle:format="plain-text"><![CDATA[\n%s\n]]></description>\n' \
            "$(cat "$notes_file")"
        printf '      <enclosure url="%s/Erst.dmg" type="application/octet-stream" %s/>\n' \
            "$base_url" "$signature"
        printf '    </item>\n  </channel>\n</rss>\n'
    } >"$release_dir/appcast.xml"
    xmllint --noout "$release_dir/appcast.xml"
}

main() {
    local local_only=false notes_file version base_url
    if [[ "${1:-}" == "--local" ]]; then
        local_only=true
        shift
    fi
    [[ $# == 1 ]] || fail "usage: scripts/release.sh [--local] NOTES_FILE"
    notes_file="$1"
    [[ -s "$notes_file" ]] || fail "$notes_file is empty or missing"
    version="$(workspace_version)"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Cargo.toml has no plain version: $version"

    if [[ "$local_only" == false ]]; then
        check_publishable "$version"
    fi
    (cd "$ERST_ROOT/app" && swift package resolve >/dev/null)
    "$ERST_ROOT/scripts/build-dmg.sh"

    rm -rf "$release_dir"
    mkdir -p "$release_dir"
    cp "$ERST_ROOT/dist/Erst.dmg" "$release_dir/Erst.dmg"
    if [[ "$local_only" == false ]]; then
        notarize "$release_dir/Erst.dmg"
    fi
    base_url="${ERST_RELEASE_BASE_URL:-https://github.com/$repository/releases/download/v$version}"
    write_appcast "$version" "$notes_file" "$release_dir/Erst.dmg" "$base_url"
    printf '==> Feed and archive for %s in %s\n' "$version" "${release_dir#"$ERST_ROOT"/}"

    if [[ "$local_only" == false ]]; then
        gh release create "v$version" "$release_dir/Erst.dmg" "$release_dir/appcast.xml" \
            --repo "$repository" --target main --title "Erst $version" --notes-file "$notes_file"
        printf '==> Published https://github.com/%s/releases/tag/v%s\n' "$repository" "$version"
    fi
}

main "$@"
