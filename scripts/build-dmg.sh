#!/usr/bin/env bash
# Build dist/Erst.dmg: the app and a link to Applications in a window drawn as the echo art.
# Pass --skip-app to package the dist/Erst.app that is already built.
set -euo pipefail
# shellcheck source=scripts/env.sh
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

app="$ERST_ROOT/dist/Erst.app"
dmg="$ERST_ROOT/dist/Erst.dmg"
work="$ERST_ROOT/.erst-dev/dmg"
venv="$ERST_ROOT/.erst-dev/dmgbuild"
# dmgbuild writes the Finder layout directly, so packaging needs no Finder scripting permission.
dmgbuild_version="1.6.5"

if [[ "${1:-}" != "--skip-app" ]]; then
    "$ERST_ROOT/scripts/build-app.sh"
fi
if [[ ! -d "$app" ]]; then
    printf 'error: %s is missing; run scripts/build-app.sh first\n' "$app" >&2
    exit 1
fi

rm -rf "$work"
mkdir -p "$work"

printf '==> Rendering the installer background\n'
(cd "$ERST_ROOT/app" && swift build -c release --product ErstSnapshots >/dev/null)
snapshots="$(cd "$ERST_ROOT/app" && swift build -c release --product ErstSnapshots --show-bin-path)/ErstSnapshots"
"$snapshots" --installer-background "$work"
# One TIFF with both resolutions, so Finder draws the 2x art on a Retina display.
tiffutil -cathidpicheck "$work/installer-background.png" "$work/installer-background@2x.png" \
    -out "$work/installer-background.tiff" >/dev/null 2>&1

if [[ ! -x "$venv/bin/dmgbuild" ]]; then
    printf '==> Installing dmgbuild %s into .erst-dev\n' "$dmgbuild_version"
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet "dmgbuild==$dmgbuild_version"
fi

printf '==> Building %s\n' "${dmg#"$ERST_ROOT"/}"
rm -f "$dmg"
"$venv/bin/dmgbuild" -s "$ERST_ROOT/scripts/dmg-settings.py" \
    -D app="$app" \
    -D background="$work/installer-background.tiff" \
    -D volume_icon="$app/Contents/Resources/Erst.icns" \
    "Erst" "$dmg"

# awk reads to the end, so codesign never writes into a closed pipe under pipefail.
identity="$(codesign -dvv "$app" 2>&1 | awk -F= '/^Authority=/ && !found { print $2; found = 1 }')"
if [[ -n "$identity" ]]; then
    codesign --force --sign "$identity" "$dmg"
    printf '==> Signed the disk image as %s\n' "$identity"
fi
printf '==> %s\n' "$dmg"
