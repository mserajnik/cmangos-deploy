# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

ARG DEBIAN_FRONTEND=noninteractive
ARG CMANGOS_EXPANSION=classic
ARG CMANGOS_CORE_REPOSITORY_URL=https://github.com/cmangos/mangos-classic.git
ARG CMANGOS_CORE_REVISION=master
ARG CMANGOS_DATABASE_REPOSITORY_URL=https://github.com/cmangos/classic-db.git
ARG CMANGOS_DATABASE_REVISION=master
ARG CMANGOS_PLAYERBOTS_REPOSITORY_URL=https://github.com/cmangos/playerbots.git
ARG CMANGOS_PLAYERBOTS_REVISION=master
ARG CMANGOS_PATCHES_REPOSITORY_URL
ARG CMANGOS_FAIL_ON_PATCH_ERROR=0
ARG CMANGOS_MIGRATION_EDITS=

FROM mariadb:11.8 AS build

ARG DEBIAN_FRONTEND
ARG CMANGOS_EXPANSION
ARG CMANGOS_CORE_REPOSITORY_URL
ARG CMANGOS_CORE_REVISION
ARG CMANGOS_DATABASE_REPOSITORY_URL
ARG CMANGOS_DATABASE_REVISION
ARG CMANGOS_PLAYERBOTS_REPOSITORY_URL
ARG CMANGOS_PLAYERBOTS_REVISION
ARG CMANGOS_PATCHES_REPOSITORY_URL
ARG CMANGOS_FAIL_ON_PATCH_ERROR

RUN \
  apt update && \
  apt install -y --no-install-recommends \
    git && \
  git clone "$CMANGOS_CORE_REPOSITORY_URL" /build/core && \
  git clone "$CMANGOS_DATABASE_REPOSITORY_URL" /build/database && \
  git clone "$CMANGOS_PLAYERBOTS_REPOSITORY_URL" /build/playerbots && \
  cd /build/core && \
  git checkout "$CMANGOS_CORE_REVISION" && \
  cd /build/database && \
  git checkout "$CMANGOS_DATABASE_REVISION" && \
  cd /build/playerbots && \
  git checkout "$CMANGOS_PLAYERBOTS_REVISION" && \
  cd /build/core && \
  if [ -n "$CMANGOS_PATCHES_REPOSITORY_URL" ]; then \
    echo "Cloning and applying patches from $CMANGOS_PATCHES_REPOSITORY_URL"; \
    git clone "$CMANGOS_PATCHES_REPOSITORY_URL" /build/patches && \
    patch_count=0 && \
    # Patches in `all` (and per-repo subdirectories under `all`) are applied to
    # every expansion; patches in `<expansion>` (and per-repo subdirectories
    # there) only to that expansion. Top-level `*.patch` files apply to
    # `/build/core`; `database/*.patch` and `playerbots/*.patch` apply to the
    # corresponding cloned source tree.
    # The expansion-specific and per-repo subdirectories are optional and may
    # not exist.
    for patch in \
      /build/patches/all/*.patch \
      /build/patches/$CMANGOS_EXPANSION/*.patch \
      /build/patches/all/database/*.patch \
      /build/patches/$CMANGOS_EXPANSION/database/*.patch \
      /build/patches/all/playerbots/*.patch \
      /build/patches/$CMANGOS_EXPANSION/playerbots/*.patch; \
    do \
      if [ -f "$patch" ]; then \
        case "$patch" in \
          */database/*) target=/build/database ;; \
          */playerbots/*) target=/build/playerbots ;; \
          *) target=/build/core ;; \
        esac; \
        echo "Applying patch $patch (to '$target')"; \
        if ! ( cd "$target" && git apply "$patch" ); then \
          echo "Failed to apply patch $patch"; \
          if [ "$CMANGOS_FAIL_ON_PATCH_ERROR" = "1" ]; then \
            exit 1; \
          fi; \
        fi; \
        patch_count=$((patch_count + 1)); \
      fi; \
    done; \
    if [ $patch_count -eq 0 ]; then \
      echo "No patches found"; \
    fi; \
  else \
    echo "No repository to apply patches from provided"; \
  fi && \
  mkdir -p /sql/core /sql/database /sql/playerbots /sql/custom && \
  cp -a /build/core/sql/base /sql/core/base && \
  cp -a /build/core/sql/updates /sql/core/updates && \
  cp -a /build/core/sql/scriptdev2 /sql/core/scriptdev2 && \
  cp -a /build/database/Full_DB /sql/database/Full_DB && \
  cp -a /build/database/Updates /sql/database/Updates && \
  cp -a /build/database/ACID /sql/database/ACID && \
  cp -a /build/database/utilities /sql/database/utilities && \
  cp -a /build/database/locales /sql/database/locales && \
  cp -a /build/playerbots/sql /sql/playerbots/sql

FROM mariadb:11.8

ARG CMANGOS_EXPANSION
ARG CMANGOS_MIGRATION_EDITS

# See https://github.com/MariaDB/mariadb-docker/blob/1b6429ba3544e134715c15f8c56cc6f665f827c9/11.8/docker-entrypoint.sh#L595-L599
ENV MARIADB_AUTO_UPGRADE=1
ENV MARIADB_USER=mangos
ENV MARIADB_PASSWORD=mangos
ENV MARIADB_ROOT_PASSWORD=password
ENV CMANGOS_REALMLIST_NAME=CMaNGOS
ENV CMANGOS_REALMLIST_ADDRESS=127.0.0.1
ENV CMANGOS_REALMLIST_PORT=8085
ENV CMANGOS_REALMLIST_ICON=1
ENV CMANGOS_REALMLIST_TIMEZONE=0
ENV CMANGOS_REALMLIST_ALLOWED_SECURITY_LEVEL=0
ENV CMANGOS_EXPANSION=$CMANGOS_EXPANSION
ENV CMANGOS_ENABLE_AUTOMATIC_WORLD_DB_CORRECTIONS=1
ENV CMANGOS_HALT_ON_MIGRATION_EDITS=1
ENV CMANGOS_PROCESS_CUSTOM_SQL=1

COPY --from=build /sql /sql

RUN \
  mkdir -p /opt/scripts && \
  mkdir /always-initdb.d && \
  printf '%s\n' "$CMANGOS_MIGRATION_EDITS" >/sql/migration-edits

COPY ./docker/database/db-functions.sh /opt/scripts
COPY --chmod=755 ./docker/database/create-db.sh /docker-entrypoint-initdb.d
COPY --chmod=755 ./docker/database/update-db.sh /always-initdb.d
COPY --chmod=755 ./docker/database/healthcheck.sh /usr/local/bin/cmangos-healthcheck
COPY --chmod=755 ./docker/database/cmangos-confirm-changes.sh /usr/local/bin/cmangos-confirm-changes

COPY --chmod=755 ./docker/database/docker-entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["mariadbd"]
