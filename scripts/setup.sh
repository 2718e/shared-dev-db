#!/usr/bin/env bash
# One-command setup for an instance on any Docker host.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
env_file=${COMPOSE_ENV_FILE:-$root/.env}
python3 "$root/scripts/configure.py" --env-file "$env_file" "$@"
"${CONTAINER_ENGINE:-docker}" compose --project-directory "$root" --env-file "$env_file" \
    up -d --wait --wait-timeout 120
