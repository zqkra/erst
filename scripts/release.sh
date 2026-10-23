#!/usr/bin/env bash
# Build, sign, notarize, and publish one release of Erst, with the feed the in-app updater reads.
#
#   scripts/release.sh NOTES_FILE                publish the version in Cargo.toml on GitHub Releases
#   scripts/release.sh --unnotarized NOTES_FILE  publish without Apple's notarization, until it arrives
#   scripts/release.sh --local NOTES_FILE        build the archive and feed in dist/release, publish nothing
#
# NOTES_FILE holds what changed, one sentence per line. Settings, About shows these lines.
# A notarized release needs ERST_SIGN_IDENTITY (a Developer ID Application identity) and
# ERST_NOTARY_PROFILE (a notarytool keychain profile). An unnotarized release is signed with the
# Erst Development certificate, never ad hoc, so permissions survive updates. docs/RELEASING.md
# has the setup.
set -euo pipefail
# shellcheck source=scripts/env.sh
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

repository="zqkra/erst"
sparkle_account="erst"
release_dir="$ERST_ROOT/dist/release"
gatekeeper_note="This build is not notarized by Apple yet; notarization is on its way. Drag Erst into \
Applications and open it. macOS stops the first launch: open System Settings, Privacy & Security, and \
click Open Anyway. Updates install without this step."

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
    local version="$1" notarized="$2"
    [[ -z "$(git -C "$ERST_ROOT" status --porcelain)" ]] || fail "commit or stash your changes first"
    [[ "$(git -C "$ERST_ROOT" branch --show-current)" == "main" ]] || fail "release from main"
    git -C "$ERST_ROOT" fetch --quiet origin main
    [[ "$(git -C "$ERST_ROOT" rev-parse HEAD)" == "$(git -C "$ERST_ROOT" rev-parse origin/main)" ]] ||
        fail "push main first, so the tag points at what you built"
    if gh release view "v$version" --repo "$repository" >/dev/null 2>&1; then
        fail "v$version is already released; raise the version in Cargo.toml"
    fi
    if [[ "$notarized" == true ]]; then
        [[ "${ERST_SIGN_IDENTITY:-}" == Developer\ ID\ Application:* ]] ||
            fail "set ERST_SIGN_IDENTITY to your Developer ID Application identity"
        [[ -n "${ERST_NOTARY_PROFILE:-}" ]] || fail "set ERST_NOTARY_PROFILE to your notarytool profile"
    fi
}

# An ad hoc signature changes with every build, so macOS would forget Erst's permissions at each
# update. A release must carry a certificate.
check_signed() {
    local authority
    # awk reads to the end, so codesign never writes into a closed pipe under pipefail.
    authority="$(codesign -dvv "$ERST_ROOT/dist/Erst.app" 2>&1 | awk -F= '/^Authority=/ && !found { print $2; found = 1 }')"
    [[ -n "$authority" ]] ||
        fail "dist/Erst.app is signed ad hoc; import the Erst Development certificate (docs/RELEASING.md)"
    printf '==> Signed by %s\n' "$authority"
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
    local publish=true notarized=true notes_file version base_url
    case "${1:-}" in
        --local)
            publish=false
            notarized=false
            shift
            ;;
        --unnotarized)
            notarized=false
            shift
            ;;
    esac
    [[ $# == 1 ]] || fail "usage: scripts/release.sh [--local | --unnotarized] NOTES_FILE"
    notes_file="$1"
    [[ -s "$notes_file" ]] || fail "$notes_file is empty or missing"
    version="$(workspace_version)"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Cargo.toml has no plain version: $version"

    if [[ "$publish" == true ]]; then
        check_publishable "$version" "$notarized"
    fi
    (cd "$ERST_ROOT/app" && swift package resolve >/dev/null)
    "$ERST_ROOT/scripts/build-dmg.sh"
    check_signed

    rm -rf "$release_dir"
    mkdir -p "$release_dir"
    cp "$ERST_ROOT/dist/Erst.dmg" "$release_dir/Erst.dmg"
    if [[ "$notarized" == true ]]; then
        notarize "$release_dir/Erst.dmg"
    fi
    base_url="${ERST_RELEASE_BASE_URL:-https://github.com/$repository/releases/download/v$version}"
    write_appcast "$version" "$notes_file" "$release_dir/Erst.dmg" "$base_url"
    # The release page carries the notes, and how to open a build Apple has not notarized.
    cp "$notes_file" "$release_dir/release-notes.md"
    if [[ "$notarized" == false ]]; then
        printf '\n%s\n' "$gatekeeper_note" >>"$release_dir/release-notes.md"
    fi
    printf '==> Feed and archive for %s in %s\n' "$version" "${release_dir#"$ERST_ROOT"/}"

    if [[ "$publish" == true ]]; then
        gh release create "v$version" "$release_dir/Erst.dmg" "$release_dir/appcast.xml" \
            --repo "$repository" --target main --title "Erst $version" \
            --notes-file "$release_dir/release-notes.md"
        printf '==> Published https://github.com/%s/releases/tag/v%s\n' "$repository" "$version"
    fi
}

main "$@"
