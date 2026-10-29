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

## Lima VM with nerdctl

Run the same Compose project inside the Lima VM using `nerdctl compose`:

```sh
cp .env.example .env.agent-vm
# Edit this file: set a private password and POSTGRES_DATA_DIR to a VM-local path.
nerdctl run --rm --entrypoint sh \
  -v /var/tmp/shared-dev-db-postgres-data:/data \
  postgres:17-alpine -c 'chown postgres:postgres /data'
nerdctl compose --env-file .env.agent-vm up -d
```

The container engine owns and manages the container; Docker does not need to
run inside the VM. `.env.agent-vm` distinguishes these settings from a host
instance's `.env`; it is ignored by Git. Keep the database data directory on
the VM filesystem to isolate it from the host instance. The ownership command
prepares a new bind mount for Lima's rootless UID mapping; run it once for a
new, empty data directory before starting PostgreSQL. `CONTAINER_ENGINE`
selects the engine for the database helper below, and `COMPOSE_ENV_FILE` points
it at the VM's settings.

## Create and connect to project databases

Create a database with:

```sh
./scripts/create-db my_project
```

For the VM instance:

```sh
CONTAINER_ENGINE=nerdctl COMPOSE_ENV_FILE=.env.agent-vm \
  ./scripts/create-db my_project
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

The image defaults to `postgres:17-alpine`; `POSTGRES_IMAGE` can select another
compatible image. This leaves room to adopt a PostgreSQL image that bundles
additional extensions later without changing the service layout. Keep a
consistent image major version for an existing data directory; upgrading a
major version requires a PostgreSQL data upgrade rather than simply changing
the image tag.
