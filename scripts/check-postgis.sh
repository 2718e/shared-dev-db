#!/usr/bin/env bash
# Integration check against a disposable database; never mounts instance data.
set -euo pipefail
name="shared-db-postgis-check-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$name" --tmpfs /var/lib/postgresql \
    -e POSTGRES_HOST_AUTH_METHOD=trust "${POSTGRES_IMAGE:-shared-dev-db:18-postgis}" >/dev/null
for attempt in {1..60}; do
    if docker exec "$name" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
    sleep 1
done
docker exec -i "$name" psql -h 127.0.0.1 -U postgres -v ON_ERROR_STOP=1 <<'SQL'
CREATE DATABASE spatial_check;
\connect spatial_check
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;
DO $$
BEGIN
    IF ST_Distance(ST_Point(0, 0), ST_Point(3, 4)) <> 5 THEN
        RAISE EXCEPTION 'Unexpected spatial distance';
    END IF;
END $$;
SELECT PostGIS_Full_Version();
\connect postgres
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_extension WHERE extname = 'postgis') THEN
        RAISE EXCEPTION 'PostGIS unexpectedly enabled in another database';
    END IF;
END $$;
SQL
