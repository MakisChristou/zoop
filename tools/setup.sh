#!/bin/sh
# Generate an installation configuration once; never overwrite an existing setup.
set -eu
cd "$(dirname "$0")/.."
if [ "${1:-}" = '--show-code' ]; then
    test -f .env || { printf 'Run tools/setup.sh first.\n' >&2; exit 1; }
    sed -n 's/^ZOOP_SETUP_CODE=//p' .env
    exit
fi
if [ -e .env ]; then
    printf '.env already exists. Edit it to change this installation.\n' >&2
    exit 1
fi
origin=${1:-http://localhost:8080}
bind=${ZOOP_BIND:-127.0.0.1}
port=${ZOOP_PORT:-8080}
# Restrict interpolation characters; the API also validates the complete origin.
case "$origin" in http://*|https://*) ;; *) printf 'Use an HTTP or HTTPS origin.\n' >&2; exit 1;; esac
for value in "$origin" "$bind" "$port"; do
    if [ "$value" != "$(printf '%s' "$value" | LC_ALL=C tr -cd '[:alnum:].:/_[]-')" ]; then
        printf 'Unsupported characters in origin, bind address or port.\n' >&2; exit 1
    fi
done
authority=${origin#*://}
case "$authority" in ''|*/*) printf 'Use an origin without a path or trailing slash.\n' >&2; exit 1;; esac
case "$port" in ''|*[!0-9]*) printf 'Use a numeric port.\n' >&2; exit 1;; esac
if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    printf 'Port must be between 1 and 65535.\n' >&2; exit 1
fi
random_hex() { od -An -N32 -tx1 /dev/urandom | tr -d ' \n'; }
umask 077
# noclobber also protects concurrent setup attempts.
set -C
{
    printf 'ZOOP_ORIGIN=%s\nZOOP_BIND=%s\nZOOP_PORT=%s\n' "$origin" "$bind" "$port"
    printf 'ZOOP_DB_PASSWORD=%s\n' "$(random_hex)"
    printf 'ZOOP_INGEST_TOKEN=%s\n' "$(random_hex)"
    printf 'ZOOP_SETUP_CODE=%s\n' "$(random_hex)"
} > .env
printf 'Configuration saved. Run docker compose up -d --build --wait.\n'
printf 'Open %s, then use ./tools/setup.sh --show-code for the setup code.\n' "$origin"
