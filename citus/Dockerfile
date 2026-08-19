# SPDX-FileCopyrightText: Copyright © contributors to CloudNativePG, established as CloudNativePG a Series of LF Projects, LLC.
# SPDX-License-Identifier: Apache-2.0

ARG BASE=ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
FROM $BASE AS builder

ARG PG_MAJOR
ARG EXT_VERSION

USER 0

# Citus has no official PGDG package, so it is built from its upstream
# source tarball instead of being installed via `apt-get`.
#
# libcurl4-openssl-dev is required at build time even though we don't want
# Citus' libcurl-based "anonymous statistics collection" telemetry: on this
# base image PostgreSQL core itself is built --with-libcurl (for libpq
# OAuth support), so its pg_config.h unconditionally defines HAVE_LIBCURL.
# Citus' statistics_collection.c guards its curl-dependent code purely on
# that same macro name, so it always compiles against curl on this base,
# regardless of Citus' own --with(out)-libcurl configure flag. The
# telemetry itself stays disabled at runtime: it also requires
# ENABLE_CITUS_STATISTICS_COLLECTION, a flag only ever set by Citus' own
# official-package build pipeline and never defined in a plain source
# build (see EnableStatisticsCollection in statistics_collection.c).
RUN set -eux; \
    # Initial system libraries, to diff against later (see postgis for the
    # same pattern).
    ldconfig -p | awk '{print $NF}' | grep '^/' | sort | uniq > /tmp/base-image-libs.out; \
    apt-get update && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      postgresql-server-dev-${PG_MAJOR} \
      libcurl4-openssl-dev \
      liblz4-dev \
      libzstd-dev \
      libicu-dev \
      libkrb5-dev \
    && rm -rf /var/lib/apt/lists/*

# Download the upstream release tarball
RUN mkdir -p /usr/src/citus && \
    curl -fsSL -o /tmp/citus.tar.gz \
      "https://github.com/citusdata/citus/archive/refs/tags/v${EXT_VERSION}.tar.gz" && \
    tar xzf /tmp/citus.tar.gz -C /usr/src/citus --strip-components=1 && \
    rm /tmp/citus.tar.gz

WORKDIR /usr/src/citus

RUN ./configure PG_CONFIG=/usr/lib/postgresql/${PG_MAJOR}/bin/pg_config && \
    make -j$(nproc) install

# Gather the runtime shared libraries citus.so/citus_columnar.so/the CDC
# decoders need that aren't already part of the base image, plus their
# license/copyright files. Mirrors the postgis Dockerfile's approach.
RUN mkdir -p /system /licenses && \
    ldd /usr/lib/postgresql/${PG_MAJOR}/lib/citus.so \
        /usr/lib/postgresql/${PG_MAJOR}/lib/citus_columnar.so \
        /usr/lib/postgresql/${PG_MAJOR}/lib/citus_decoders/*.so \
        | awk '{print $3}' | grep '^/' | sort | uniq > /tmp/all-deps.out && \
    comm -13 /tmp/base-image-libs.out /tmp/all-deps.out > /tmp/libraries.out && \
    while read -r lib; do \
        resolved=$(readlink -f "$lib"); \
        dir=$(dirname "$lib"); \
        base=$(basename "$lib"); \
        cp -a "$resolved" /system/; \
        for file in "$dir"/"${base%.so*}.so"*; do \
            [ -e "$file" ] || continue; \
            if [ -L "$file" ] && [ "$(readlink -f "$file")" = "$resolved" ]; then \
                ln -sf "$(basename "$resolved")" "/system/$(basename "$file")"; \
            fi; \
        done; \
    done < /tmp/libraries.out && \
    for lib in $(find /system -maxdepth 1 -type f -name '*.so*'); do \
        pkg=$(dpkg -S "$(basename "$lib")" | grep -v "diversion by" | awk -F: '/:/{print $1; exit}'); \
        [ -z "$pkg" ] && continue; \
        mkdir -p "/licenses/$pkg" && cp -a "/usr/share/doc/$pkg/copyright" "/licenses/$pkg/copyright"; \
    done

FROM scratch
ARG PG_MAJOR

# Licenses
COPY --from=builder /usr/src/citus/LICENSE /licenses/citus/LICENSE
COPY --from=builder /licenses /licenses/

# Libraries
# NOTE: citus_decoders/ is copied separately (not via a "citus*" glob):
# Docker COPY copies a matched *directory*'s contents, not the directory
# itself, so a glob also matching citus_decoders/ would flatten its
# pgoutput.so/wal2json.so straight into /lib, shadowing the real core
# logical-decoding plugins.
COPY --from=builder \
      /usr/lib/postgresql/${PG_MAJOR}/lib/citus.so \
      /usr/lib/postgresql/${PG_MAJOR}/lib/citus_columnar.so \
      /usr/lib/postgresql/${PG_MAJOR}/lib/citus_pgoutput.so \
      /usr/lib/postgresql/${PG_MAJOR}/lib/citus_wal2json.so \
      /lib/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/citus_decoders/ /lib/citus_decoders/
COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/bitcode/ /lib/bitcode/

# System libs not already present in the base image (libcurl and its
# transitive closure - see the builder stage above)
COPY --from=builder /system /system/

# Share
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/citus* /share/extension/

USER 65532:65532
