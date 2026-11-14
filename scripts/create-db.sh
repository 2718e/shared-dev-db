#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 DATABASE_NAME" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
database_name=$1

# Keep names predictable and avoid accepting SQL fragments. PostgreSQL allows
# more names, but this covers ordinary project database names.
if [[ ! $database_name =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || (( ${#database_name} > 63 )); then
  echo "Database name must start with a letter or underscore and contain only letters, numbers, and underscores (maximum 63 characters)." >&2
  exit 2
fi

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
engine=${CONTAINER_ENGINE:-docker}
env_file=${COMPOSE_ENV_FILE:-$root/.env}
compose=("$engine" compose --project-directory "$root" --env-file "$env_file")
if [[ ! -f $env_file ]]; then
  echo "Missing $env_file. Run scripts/setup.sh first." >&2
  exit 1
fi

# Use the container's actual role; let Compose parse dotenv configuration.
psql=(exec -T postgres sh -c 'exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres "$@"' sh)

exists=$("${compose[@]}" "${psql[@]}" \
  -tAc "SELECT 1 FROM pg_database WHERE datname = '$database_name'")
if [[ $exists == 1 ]]; then
  echo "Database '$database_name' already exists."
  exit 0
fi

"${compose[@]}" "${psql[@]}" \
  -c "CREATE DATABASE \"$database_name\""
echo "Created database '$database_name'."
