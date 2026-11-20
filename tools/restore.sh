#!/bin/sh
# Restore into an empty installation only. Never overwrite existing health data.
set -eu
cd "$(dirname "$0")/.."
file=${1:?Usage: tools/restore.sh /path/to/zoop.dump}
test -f "$file"
tables=$(docker compose exec -T database psql -U zoop -d zoop -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
if [ "$tables" != 0 ]; then
    printf 'Restore requires an empty database. Existing data was not changed.\n' >&2
    exit 1
fi
docker compose exec -T database pg_restore -U zoop -d zoop --no-owner --no-acl --exit-on-error --single-transaction < "$file"
printf 'Restore complete. Start the full stack to apply any newer migrations.\n'
