#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
file=${1:?Usage: tools/backup.sh /path/to/zoop.dump}
umask 077
test ! -e "$file" || { printf 'Backup file already exists.\n' >&2; exit 1; }
temporary=$(mktemp "${file}.tmp.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
docker compose exec -T database pg_dump -U zoop -d zoop --format=custom > "$temporary"
# The hard link publishes a complete dump and atomically refuses an existing name.
ln "$temporary" "$file"
printf 'Backup saved to %s\n' "$file"
