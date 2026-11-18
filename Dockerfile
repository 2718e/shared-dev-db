# Keep PostgreSQL's Alpine ABI and data layout; add extension packages here.
FROM postgres:18-alpine3.24

ARG POSTGIS_VERSION=3.6.4
ARG POSTGIS_SHA256=ed8dc6679f1e06f7b113592b04cde2a7e00f1b1e681294c8ca2204058990cec6

# Build against this image's /usr/local PostgreSQL, not Alpine's packaged server.
# Raster and SFCGAL are optional and deliberately excluded from this core build.
RUN set -eux; \
    apk add --no-cache geos proj json-c libstdc++ protobuf-c pgbackrest; \
    apk add --no-cache --virtual .postgis-build-deps \
        ca-certificates curl tar g++ make perl \
        geos-dev proj-dev json-c-dev libxml2-dev protobuf-c-dev \
        $DOCKER_PG_LLVM_DEPS; \
    curl -fsSL "https://download.osgeo.org/postgis/source/postgis-${POSTGIS_VERSION}.tar.gz" -o /tmp/postgis.tar.gz; \
    echo "${POSTGIS_SHA256}  /tmp/postgis.tar.gz" | sha256sum -c -; \
    mkdir /tmp/postgis; \
    tar -xzf /tmp/postgis.tar.gz -C /tmp/postgis --strip-components=1; \
    cd /tmp/postgis; \
    ./configure --without-raster --without-sfcgal --without-address-standardizer; \
    make -j2; \
    make install; \
    cd /; \
    rm -rf /tmp/postgis /tmp/postgis.tar.gz; \
    apk del .postgis-build-deps

COPY pgbackrest.conf /etc/pgbackrest/pgbackrest.conf
