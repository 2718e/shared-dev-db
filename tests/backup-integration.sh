#!/usr/bin/env bash
# Disposable end-to-end test; builds an image and creates a temporary cluster.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
project="sdb-backup-test-$$"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
mkdir "$tmp/data" "$tmp/repo"
chmod 777 "$tmp" "$tmp/repo"
cat > "$tmp/env" <<EOF
POSTGRES_USER=dev
POSTGRES_PASSWORD=temporary-test-password
POSTGRES_DB=postgres
POSTGRES_DATA_DIR=$tmp/data
POSTGRES_PORT=$port
POSTGRES_IMAGE=shared-dev-db-backup-test:local
BACKUP_REPO_DIR=$tmp/repo
EOF
compose=(docker compose --project-name "$project" --project-directory "$root" --env-file "$tmp/env" -f "$root/compose.yaml" -f "$root/compose.backup.yaml")
cleanup() {
    "${compose[@]}" down -v --remove-orphans >/dev/null || true
    docker run --rm -v "$tmp:/work" busybox rm -rf /work/data /work/repo || true
    rm -rf "$tmp"
}
trap cleanup EXIT
"${compose[@]}" build
"${compose[@]}" up -d --wait --wait-timeout 120
"${compose[@]}" exec -T postgres psql -U dev -d postgres -v ON_ERROR_STOP=1 -c 'CREATE DATABASE first_project'
COMPOSE_PROJECT_NAME="$project" COMPOSE_ENV_FILE="$tmp/env" bash "$root/scripts/backup.sh" full
"${compose[@]}" exec -T postgres psql -U dev -d postgres -v ON_ERROR_STOP=1 -c 'CREATE DATABASE second_project'
COMPOSE_PROJECT_NAME="$project" COMPOSE_ENV_FILE="$tmp/env" bash "$root/scripts/backup.sh" incr
"${compose[@]}" exec -T -u postgres postgres sh -ec '
    mkdir /tmp/restore-test
    pgbackrest --stanza=shared-dev-db --pg1-path=/tmp/restore-test restore
    pg_ctl -D /tmp/restore-test -o "-p 5544 -k /tmp" -w start
    trap "pg_ctl -D /tmp/restore-test -m fast -w stop" EXIT
    psql -h /tmp -p 5544 -U dev -d postgres -Atc "SELECT datname FROM pg_database" > /tmp/restored-databases
    grep -qx first_project /tmp/restored-databases
    grep -qx second_project /tmp/restored-databases
'
