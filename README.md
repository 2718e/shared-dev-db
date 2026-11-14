# Shared development PostgreSQL

One PostgreSQL server serves multiple project databases using a custom image based on the official
PostgreSQL Alpine image. This project works on any Docker host; storage paths and VM
lifecycle belong to the caller.

## Setup

With Docker Compose and Python 3 installed, run:

```sh
./scripts/setup.sh
```

This generates a private `.env` with a random password, starts PostgreSQL, and
waits for it to become healthy. Rerunning preserves existing settings, credentials,
and data. The default data directory is `data/` and the listener is
`127.0.0.1:5432`. To choose persistent storage on the first run:

```sh
./scripts/setup.sh --data-dir /absolute/path/to/postgres18
```

You can instead copy `.env.example` to `.env` and edit it before setup. An
existing settings file is never replaced. If data exists but settings are missing,
setup refuses to generate a replacement password; restore the original settings.
Changing a password in the settings file does not change an initialized server's
password; use PostgreSQL to change it too.

## Create and connect to project databases

```sh
./scripts/create-db.sh my_project
. ./.env.connection
psql "${SHARED_DEV_DB_BASE_URL}my_project"
```

The helper is safe to rerun. Database names use letters, digits and underscores,
start with a letter or underscore, and are at most 63 characters. It can be
invoked by absolute path from another working directory.

`SHARED_DEV_DB_BASE_URL` includes URL-encoded credentials, host, port, and a
trailing `/`; append the project database name. Setup writes this environment
into a private `.env.connection` file. It contains credentials, so keep it private.
A project can set `DATABASE_URL="${SHARED_DEV_DB_BASE_URL}my_project"` as needed;
setup does not select a project database globally.

## External settings and multiple instances

For a read-only checkout or a separate instance:

```sh
COMPOSE_ENV_FILE=/path/to/settings.env ./scripts/setup.sh \
  --data-dir /path/to/persistent/postgres18
COMPOSE_ENV_FILE=/path/to/settings.env ./scripts/create-db.sh my_project
. /path/to/settings.env.connection
```

The connection file defaults to the settings filename plus `.connection`.
`--connection-file PATH` selects another location. The lower-level
`python3 scripts/configure.py` accepts the same flags and initializes settings
without starting containers, for callers managing their own service lifecycle.
`--require-data-dir` also checks that existing settings use the requested path.

Each instance needs separate settings, storage, and a Compose project name
(`COMPOSE_PROJECT_NAME`). Choose a different `POSTGRES_PORT` when sharing a host.
Set `CONTAINER_ENGINE` to use a compatible engine for the scripts. Compose parses
settings and applies its usual environment interpolation; use the same overrides
for configuration, startup, and database creation.

## Data and image configuration

`POSTGRES_DATA_DIR` is mounted at `/var/lib/postgresql`, the official image layout
for PostgreSQL 18+. Compose builds `shared-dev-db:18-postgis` from the official
`postgres:18-alpine3.24` image, adding PostGIS 3.6.4 compiled against its server.
`POSTGRES_IMAGE` overrides the local build tag. Add future extensions to the
Dockerfile. Core PostGIS and topology are available; raster, SFCGAL, and address
standardizer are excluded. No extensions are automatically enabled in databases. Do not point two instances
at the same directory. Keep a consistent image major version for existing data;
a major version change requires a PostgreSQL upgrade, not just an image tag edit.

Bind to loopback unless remote access is deliberately needed. Stop with
`docker compose stop` (include `--env-file PATH` for external settings). Back up
with PostgreSQL's tools for a live instance, or copy its data while stopped.
Persistence across machine replacement depends on the chosen storage.

Run configuration tests with `python3 -m unittest discover -s tests -v`.
The Compose integration check needs Docker Compose but does not start containers.

## Enable geospatial features

Image installation makes extensions available server-wide; enable them separately
in each database, including databases that already exist:

```sh
. ./.env.connection
psql "${SHARED_DEV_DB_BASE_URL}property_search" -v ON_ERROR_STOP=1 \
  -c 'CREATE EXTENSION IF NOT EXISTS postgis;' \
  -c 'SELECT PostGIS_Full_Version();'
```

Use `CREATE EXTENSION IF NOT EXISTS postgis_topology;` only if a project needs
topology. Other project databases remain opt-in. Rebuild with
`docker compose build --pull` (include your external `--env-file` if used),
then run setup to recreate the container using the existing data and credentials.
Existing PostGIS installations need `ALTER EXTENSION postgis UPDATE;` after
upgrading PostGIS. Keep PostgreSQL's major version and Alpine family compatible
with the existing data.

After building, run `bash scripts/check-postgis.sh` to verify extension loading,
spatial calculations, topology, and per-database isolation in a disposable server.
