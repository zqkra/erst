#!/usr/bin/env bash
# Build the app bundle and open it with the development data directory.
set -euo pipefail
# shellcheck source=scripts/env.sh
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$ERST_ROOT"

"$ERST_ROOT/scripts/build-app.sh"

data_dir="$ERST_ROOT/.erst-dev"
mkdir -p "$data_dir"

if pgrep -x Erst >/dev/null 2>&1; then
    printf '==> Quitting the running Erst instance\n'
    pkill -x Erst 2>/dev/null || true
    sleep 1
fi

printf '==> Opening %s\n' "$ERST_ROOT/dist/Erst.app"
open --env "ERST_DATA_DIR=$data_dir" "$ERST_ROOT/dist/Erst.app"

printf '==> Streaming Erst logs (Ctrl-C to stop)\n'
exec log stream --style compact --level debug --predicate 'subsystem == "app.erst.Erst"'
