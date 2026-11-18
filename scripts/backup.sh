#!/usr/bin/env bash
# Run against an already started instance using compose.backup.yaml.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
env_file=${COMPOSE_ENV_FILE:-$root/.env}
type=${1:-incr}
case "$type" in full|diff|incr) ;; *) echo 'Usage: backup.sh [full|diff|incr]' >&2; exit 2;; esac
compose=("${CONTAINER_ENGINE:-docker}" compose --project-directory "$root" --env-file "$env_file" -f "$root/compose.yaml" -f "$root/compose.backup.yaml")
# Compose exec does not apply the overlay to an already running container.
# Refuse to write a seemingly successful backup into its ephemeral filesystem.
if ! "${compose[@]}" exec -T postgres mountpoint -q /var/lib/pgbackrest; then
    echo 'Backup repository is not mounted in the running container; start it with compose.backup.yaml first.' >&2
    exit 1
fi
"${compose[@]}" exec -T -u postgres postgres pgbackrest --stanza=shared-dev-db stanza-create
"${compose[@]}" exec -T -u postgres postgres pgbackrest --stanza=shared-dev-db check
"${compose[@]}" exec -T -u postgres postgres pgbackrest --stanza=shared-dev-db --type="$type" backup
