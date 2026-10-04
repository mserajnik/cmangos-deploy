# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

ARG DEBIAN_FRONTEND=noninteractive
ARG CMANGOS_EXPANSION=classic
ARG CMANGOS_CORE_REPOSITORY_URL=https://github.com/cmangos/mangos-classic.git
ARG CMANGOS_CORE_REVISION=master
ARG CMANGOS_PLAYERBOTS_REPOSITORY_URL=https://github.com/cmangos/playerbots.git
ARG CMANGOS_PLAYERBOTS_REVISION=master
ARG CMANGOS_FAIL_ON_PATCH_ERROR=0

FROM ubuntu:26.04 AS build

ARG DEBIAN_FRONTEND
ARG CMANGOS_EXPANSION
ARG CMANGOS_CORE_REPOSITORY_URL
ARG CMANGOS_CORE_REVISION
ARG CMANGOS_PLAYERBOTS_REPOSITORY_URL
ARG CMANGOS_PLAYERBOTS_REVISION
ARG CMANGOS_FAIL_ON_PATCH_ERROR

COPY ./docker/patches /build/patches

RUN \
  apt update && \
  apt install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    git \
    libboost-all-dev \
    libbz2-dev \
    libcurl4-openssl-dev \
    libicu-dev \
    libmysqlclient-dev \
    libssl-dev && \
  git clone "$CMANGOS_CORE_REPOSITORY_URL" /build/core && \
  git clone "$CMANGOS_PLAYERBOTS_REPOSITORY_URL" /build/playerbots && \
  cd /build/core && \
  git checkout "$CMANGOS_CORE_REVISION" && \
  cd /build/playerbots && \
  git checkout "$CMANGOS_PLAYERBOTS_REVISION" && \
  mkdir -p /build/core/src/modules && \
  cp -a /build/playerbots /build/core/src/modules/PlayerBots && \
  cd /build/core && \
  patch_count=0 && \
  # Patches in `all/` apply to every expansion, those in `<expansion>/` to that
  # one. Top-level patches apply to the core, those in `playerbots/` to the
  # copy in `src/modules/PlayerBots/` that the build compiles. Every directory
  # is optional.
  for patch in \
    /build/patches/all/*.patch \
    /build/patches/"$CMANGOS_EXPANSION"/*.patch \
    /build/patches/all/playerbots/*.patch \
    /build/patches/"$CMANGOS_EXPANSION"/playerbots/*.patch; \
  do \
    if [ -f "$patch" ]; then \
      case "$patch" in \
        */playerbots/*) target=/build/core/src/modules/PlayerBots ;; \
        *) target=/build/core ;; \
      esac; \
      echo "Applying patch '$patch' to '$target'."; \
      if ! ( cd "$target" && git apply "$patch" ); then \
        echo "Failed to apply patch '$patch'."; \
        if [ "$CMANGOS_FAIL_ON_PATCH_ERROR" = "1" ]; then \
          exit 1; \
        fi; \
      fi; \
      patch_count=$((patch_count + 1)); \
    fi; \
  done && \
  if [ "$patch_count" -eq 0 ]; then \
    echo "No patches found."; \
  fi && \
  mkdir -p \
    /opt/cmangos/config \
    /opt/cmangos/storage/logs && \
  mkdir /build/core/build && \
  cd /build/core/build && \
  cmake \
    -B . \
    -S .. \
    -DCMAKE_INSTALL_PREFIX=/opt/cmangos \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
    -DBUILD_AHBOT=ON \
    -DBUILD_EXTRACTORS=ON \
    -DBUILD_PLAYERBOTS=ON \
    # Without this, `FetchContent` checks out Playerbots' `master`, which drops
    # the pin and the patches.
    -DFETCHCONTENT_SOURCE_DIR_PLAYERBOTS=/build/core/src/modules/PlayerBots && \
  cmake --build . -j"$(nproc)" && \
  cmake --install . && \
  # Upstream installs the per-map settings that `MoveMapGen.sh` passes to
  # `MoveMapGen` only for MSVC builds.
  cp ../contrib/extractor_scripts/config.json /opt/cmangos/bin/tools/

FROM ubuntu:26.04

ARG DEBIAN_FRONTEND
ARG CMANGOS_EXPANSION

ENV CMANGOS_EXPANSION=$CMANGOS_EXPANSION

RUN \
  apt update && \
  apt install -y --no-install-recommends \
    ca-certificates \
    libboost-filesystem1.90.0 \
    libboost-program-options1.90.0 \
    libboost-regex1.90.0 \
    libboost-serialization1.90.0 \
    libboost-thread1.90.0 \
    libbz2-1.0 \
    libcurl4t64 \
    libicu78 \
    libmysqlclient24 \
    libssl3t64 \
    netcat-openbsd \
    tzdata && \
  # The image's `ubuntu` user already has UID and GID 1000.
  groupmod -n cmangos ubuntu && \
  usermod -l cmangos -d /home/cmangos -m ubuntu && \
  apt autoremove -y && \
  apt clean -y && \
  rm -rf /var/lib/apt/lists/*

# The configuration files come from a bind mount. `include/`, `lib/`, and
# `share/` can hold libraries CMaNGOS bundles, which the image does not need.
COPY \
  --from=build \
  --exclude=cmangos/etc* \
  --exclude=cmangos/include* \
  --exclude=cmangos/lib* \
  --exclude=cmangos/share* \
  --chown=cmangos:cmangos \
  /opt /opt

COPY ./docker/check-deploy-version.sh /usr/local/lib/cmangos-deploy/check-deploy-version.sh
COPY ./docker/server/drop-privileges.sh /usr/local/lib/cmangos-deploy/drop-privileges.sh
COPY --chmod=755 ./docker/server/docker-cmd-mangosd.sh /usr/local/bin/mangosd
COPY --chmod=755 ./docker/server/docker-cmd-realmd.sh /usr/local/bin/realmd
COPY --chmod=755 ./docker/server/docker-cmd-extract-client-data.sh /usr/local/bin/extract-client-data
COPY --chmod=755 ./docker/server/docker-cmd-check-deploy-version.sh /usr/local/bin/check-deploy-version
# Ubuntu keeps package license information under `/usr/share/doc`.
COPY ./docker/docker-notice.txt /usr/share/doc/cmangos-deploy/NOTICE

WORKDIR /home/cmangos
CMD ["mangosd"]
