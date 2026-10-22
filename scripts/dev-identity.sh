#!/usr/bin/env bash
# Install a stable local signing identity without changing certificate trust.
set -euo pipefail
# shellcheck source=scripts/env.sh
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

keychain="$HOME/Library/Keychains/login.keychain-db"
if [[ $# == 2 && "$1" == "--keychain" && -n "$2" ]]; then
    keychain="$2"
elif [[ $# != 0 ]]; then
    printf 'usage: %s [--keychain <path>]\n' "$0" >&2
    exit 64
fi
if [[ ! -f "$keychain" ]]; then
    printf 'error: create and unlock the keychain first: %s\n' "$keychain" >&2
    exit 1
fi

identities="$(security find-identity -p codesigning "$keychain")"
identity="$(awk '
    /"Erst Development"/ && length($2) == 40 && $2 !~ /[^[:xdigit:]]/ {
        print $2; exit
    }
' <<< "$identities")"
if [[ -n "$identity" ]]; then
    printf 'Erst Development already exists in %s (%s)\n' "$keychain" "$identity"
    exit 0
fi

umask 077
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/erst-identity.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cat > "$tmp_dir/openssl.cnf" <<'CONFIG'
[req]
prompt = no
distinguished_name = subject
x509_extensions = code_signing

[subject]
CN = Erst Development

[code_signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG

printf '==> Creating Erst Development (RSA 2048, valid for 10 years)\n'
openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config "$tmp_dir/openssl.cnf" -keyout "$tmp_dir/key.pem" -out "$tmp_dir/cert.pem" \
    2> "$tmp_dir/openssl.log" || { cat "$tmp_dir/openssl.log" >&2; exit 1; }
openssl rand -hex 24 > "$tmp_dir/password"
# Security.framework cannot import OpenSSL's newer default PKCS#12 encryption.
openssl pkcs12 -export -name 'Erst Development' \
    -inkey "$tmp_dir/key.pem" -in "$tmp_dir/cert.pem" -out "$tmp_dir/identity.p12" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "file:$tmp_dir/password"

printf '==> Importing into %s\n' "$keychain"
security import "$tmp_dir/identity.p12" -k "$keychain" \
    -P "$(cat "$tmp_dir/password")" -T /usr/bin/codesign
printf 'Erst Development installed in %s\n' "$keychain"
