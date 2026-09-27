# check=skip=SecretsUsedInArgOrEnv
# The MariaDB defaults below are placeholders a user overrides in
# `compose.yaml`, not secrets. This directive has to precede the license
# header, because the builder stops reading directives at the first ordinary
# line.

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

FROM mariadb:12.3 AS build

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

COPY ./docker/patches /build/patches

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
  # The bundled patches apply to every build. A custom build can also name a
  # repository with additional patches in the same layout, which apply after
  # the bundled ones.
  if [ -n "$CMANGOS_PATCHES_REPOSITORY_URL" ]; then \
    echo "Cloning additional patches from $CMANGOS_PATCHES_REPOSITORY_URL"; \
    git clone "$CMANGOS_PATCHES_REPOSITORY_URL" /build/additional-patches || exit 1; \
  fi && \
  patch_count=0 && \
  additional_patch_count=0 && \
  # Patches in `all` (and per-repo subdirectories under `all`) are applied to
  # every expansion; patches in `<expansion>` (and per-repo subdirectories
  # there) only to that expansion. Top-level `*.patch` files apply to
  # `/build/core`; `database/*.patch` and `playerbots/*.patch` apply to the
  # corresponding cloned source tree.
  # The expansion-specific and per-repo subdirectories are optional and may not
  # exist.
  for patches_dir in /build/patches /build/additional-patches; do \
    for patch in \
      "$patches_dir"/all/*.patch \
      "$patches_dir"/"$CMANGOS_EXPANSION"/*.patch \
      "$patches_dir"/all/database/*.patch \
      "$patches_dir"/"$CMANGOS_EXPANSION"/database/*.patch \
      "$patches_dir"/all/playerbots/*.patch \
      "$patches_dir"/"$CMANGOS_EXPANSION"/playerbots/*.patch; \
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
        case "$patch" in \
          /build/additional-patches/*) additional_patch_count=$((additional_patch_count + 1)) ;; \
        esac; \
      fi; \
    done; \
  done && \
  if [ "$patch_count" -eq 0 ]; then \
    echo "No patches found"; \
  fi && \
  if [ -n "$CMANGOS_PATCHES_REPOSITORY_URL" ] && [ "$additional_patch_count" -eq 0 ]; then \
    echo "No additional patches found"; \
  fi && \
  mkdir -p /sql/core /sql/custom /sql/database /sql/playerbots && \
  cp -a /build/core/sql/base /sql/core/base && \
  cp -a /build/core/sql/updates /sql/core/updates && \
  cp -a /build/core/sql/scriptdev2 /sql/core/scriptdev2 && \
  cp -a /build/database/Full_DB /sql/database/Full_DB && \
  cp -a /build/database/Updates /sql/database/Updates && \
  cp -a /build/database/ACID /sql/database/ACID && \
  cp -a /build/database/utilities /sql/database/utilities && \
  cp -a /build/database/locales /sql/database/locales && \
  cp -a /build/playerbots/sql /sql/playerbots/sql

FROM mariadb:12.3

ARG CMANGOS_EXPANSION
ARG CMANGOS_MIGRATION_EDITS

# See https://github.com/MariaDB/mariadb-docker/blob/063eb10da092170beea08d2c629b6eb79d28cceb/12.3/docker-entrypoint.sh#L595-L599
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
# Ubuntu keeps package license information under `/usr/share/doc`.
COPY ./docker/docker-notice.txt /usr/share/doc/cmangos-deploy/NOTICE

COPY --chmod=755 ./docker/database/docker-entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["mariadbd"]
