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
if [[ ! $database_name =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
  echo "Database name must start with a letter or underscore and contain only letters, numbers, and underscores." >&2
  exit 2
fi

engine=${CONTAINER_ENGINE:-docker}
compose=("$engine" compose)
env_file=${COMPOSE_ENV_FILE:-.env}
if [[ $env_file != .env ]]; then
  compose+=(--env-file "$env_file")
fi

# Load the configured role from .env, without sourcing shell code from it.
if [[ ! -f $env_file ]]; then
  echo "Missing $env_file. Copy .env.example there and set POSTGRES_PASSWORD first." >&2
  exit 1
fi
postgres_user=$(sed -n 's/^POSTGRES_USER=//p' "$env_file" | tail -n 1)
postgres_user=${postgres_user:-dev}

if "${compose[@]}" exec -T postgres psql -U "$postgres_user" -d postgres \
  -tAc "SELECT 1 FROM pg_database WHERE datname = '$database_name'" | grep -q 1; then
  echo "Database '$database_name' already exists."
  exit 0
fi

"${compose[@]}" exec -T postgres psql -U "$postgres_user" -d postgres \
  -c "CREATE DATABASE \"$database_name\""
echo "Created database '$database_name'."
