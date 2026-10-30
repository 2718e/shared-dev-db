# Shared development PostgreSQL

This repository runs one PostgreSQL server for multiple project databases. Each
project gets a database on the shared server instead of its own database
container. The server uses the official PostgreSQL image and persists its data
in a configurable host-side directory.

## Start an instance

Copy `.env.example` to `.env`, set a private `POSTGRES_PASSWORD`, and choose a
`POSTGRES_DATA_DIR` for this instance. Then start it with Docker Compose:

```sh
cp .env.example .env
# Edit .env, especially POSTGRES_PASSWORD and POSTGRES_DATA_DIR.
docker compose up -d
```

The default listener is `127.0.0.1:5432`. The health check reports when
PostgreSQL is ready. To start a second independent copy, give it a separate
working directory or Compose project name, a different data directory, and a
different host port if both ports are forwarded onto the same host.

## Configuration outside the repository

An environment file can live outside the repository, for example when the
repository is read-only. Choose a writable persistent data directory and set
`POSTGRES_DATA_DIR` to its absolute path in that file. Then run:

```sh
docker compose --env-file /path/to/settings.env up -d
COMPOSE_ENV_FILE=/path/to/settings.env ./scripts/create-db.sh my_project
```

The same configuration works wherever Docker is running. For another compatible
engine, set `CONTAINER_ENGINE` for the helper and use that engine's Compose
command. Each instance needs its own data directory and credentials. Persistence
across machine or VM replacement depends on where that directory is stored.

## Create and connect to project databases

Create a database with:

```sh
./scripts/create-db.sh my_project
```

The helper is safe to rerun; it reports when the database already exists.
Connect from the host running the container engine with the credentials in
`.env`, for example:

```sh
psql "postgresql://dev:YOUR_PASSWORD@127.0.0.1:5432/my_project"
```

Set `POSTGRES_PORT` in `.env` to change the published port. Set
`POSTGRES_BIND_ADDRESS` only when clients on another network interface need to
connect; the default loopback binding avoids exposing the server to the local
network.

## Data and image configuration

`POSTGRES_DATA_DIR` is the host-side directory mounted for PostgreSQL's data.
Set it to an absolute path to choose a location outside this repository. Do not
point two running instances at the same directory. Back up this directory while
PostgreSQL is stopped, or use PostgreSQL's backup tools for a live instance.

The image defaults to `postgres:18-alpine`; `POSTGRES_IMAGE` can select another
compatible PostgreSQL 18+ image. The data directory is mounted at
`/var/lib/postgresql`, the layout used by the official image for 18 and later.
The earlier 17 image used a different mount location. This leaves room to adopt a PostgreSQL image that bundles
additional extensions later without changing the service layout. Keep a
consistent image major version for an existing data directory; upgrading a
major version requires a PostgreSQL data upgrade rather than simply changing
the image tag.
