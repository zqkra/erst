#!/usr/bin/env bash
# Mechanical enforcement of docs/HYGIENE.md. Prints every violation as
# "path:line: rule" and exits non-zero when there is at least one. Design and
# naming rules need review and are not checked here.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$ERST_ROOT"

status=0
em_dash=$'\xe2\x80\x94'
generated_swift="app/Sources/ErstCore/erst_ffi.swift"

# Reads grep output ("path:line:text") and prints "path:line: rule".
report_hits() {
    local rule="$1" hit file line
    while IFS= read -r hit; do
        if [[ -z "$hit" ]]; then
            continue
        fi
        file=${hit%%:*}
        line=${hit#*:}
        line=${line%%:*}
        printf '%s:%s: %s\n' "$file" "$line" "$rule"
        status=1
    done
}

# Em dash: every text file in the tree, tracked or not, per docs/HYGIENE.md.
# grep -I skips binaries and LICENSE is third-party text that stays untouched.
text_files=()
while IFS= read -r -d '' path; do
    [[ "$path" == "LICENSE" ]] && continue
    [[ -f "$path" ]] || continue
    text_files+=("$path")
done < <(git ls-files -z --cached --others --exclude-standard)

if ((${#text_files[@]})); then
    report_hits 'em dash (U+2014) is banned' \
        < <(grep -In -- "$em_dash" "${text_files[@]}" 2>/dev/null || true)
fi

# Swift macros that need the Xcode-only compiler plugin.
report_hits '@State is banned (needs Xcode)' \
    < <(grep -rInF -- '@State ' app/Sources 2>/dev/null || true)
report_hits '#Preview is banned (needs Xcode)' \
    < <(grep -rInF -- '#Preview' app/Sources 2>/dev/null || true)

# File size: tracked and untracked source files, generated bindings excluded.
# Swift allows at most 400 lines, Rust at most 600.
source_files=()
while IFS= read -r -d '' path; do
    [[ -f "$path" && -s "$path" ]] || continue
    case "$path" in
        *.swift | *.rs) source_files+=("$path") ;;
    esac
done < <(git ls-files -z --cached --others --exclude-standard)

if ((${#source_files[@]})); then
    while IFS= read -r hit; do
        if [[ -n "$hit" ]]; then
            printf '%s\n' "$hit"
            status=1
        fi
    done < <(awk -v generated="$generated_swift" '
        FNR == 1 {
            if (NR > 1) report(previous, lines)
            previous = FILENAME
        }
        { lines = FNR }
        END { if (NR > 0) report(previous, lines) }
        function report(file, count, limit, kind) {
            if (file == generated) return
            if (file ~ /[.]swift$/) { kind = "Swift"; limit = 400 }
            else { kind = "Rust"; limit = 600 }
            if (count > limit) {
                printf "%s:1: %s file has %d lines (over %d)\n", file, kind, count, limit
            }
        }
    ' "${source_files[@]}")
fi

# print() belongs to the ErstSnapshots and ErstProbe development tools only.
# The word boundary keeps fingerprint() and similar names out of the result.
report_hits 'print( is only allowed in ErstSnapshots and ErstProbe' \
    < <(grep -rInE --exclude-dir=ErstSnapshots --exclude-dir=ErstProbe \
        -- '(^|[^A-Za-z0-9_])print\(' app/Sources \
        2>/dev/null || true)

# Markers in code. The checker spells the banned words itself and the generated
# UniFFI binding carries one upstream marker, so both are excluded.
report_hits 'TODO, FIXME, and XXX are banned in code' \
    < <(grep -rInE --include='*.swift' --include='*.rs' --include='*.sh' \
        --include='*.c' --include='*.h' --include='*.modulemap' --include='*.toml' \
        --exclude=hygiene.sh --exclude=erst_ffi.swift \
        -- '\b(TODO|FIXME|XXX)\b' \
        app/Sources crates scripts app/Package.swift \
        2>/dev/null || true)

# Force unwraps and try! are covered by swift format lint (NeverForceUnwrap, NeverUseForceTry) in check.sh.

exit "$status"
