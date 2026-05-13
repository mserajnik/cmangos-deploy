# cmangos-deploy
# Copyright (C) 2026  Michael Serajnik  https://github.com/mserajnik

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

ARG DEBIAN_FRONTEND=noninteractive
ARG CMANGOS_EXPANSION=classic
ARG CMANGOS_CORE_REPOSITORY_URL=https://github.com/cmangos/mangos-classic.git
ARG CMANGOS_CORE_REVISION=master
ARG CMANGOS_PLAYERBOTS_REPOSITORY_URL=https://github.com/cmangos/playerbots.git
ARG CMANGOS_PLAYERBOTS_REVISION=master
ARG CMANGOS_PATCHES_REPOSITORY_URL
ARG CMANGOS_FAIL_ON_PATCH_ERROR=0
ARG CMANGOS_USER_ID=1000
ARG CMANGOS_GROUP_ID=1000
ARG CMANGOS_USER_NAME=cmangos
ARG CMANGOS_GROUP_NAME=cmangos

FROM ubuntu:26.04 AS build

ARG DEBIAN_FRONTEND
ARG CMANGOS_EXPANSION
ARG CMANGOS_CORE_REPOSITORY_URL
ARG CMANGOS_CORE_REVISION
ARG CMANGOS_PLAYERBOTS_REPOSITORY_URL
ARG CMANGOS_PLAYERBOTS_REVISION
ARG CMANGOS_PATCHES_REPOSITORY_URL
ARG CMANGOS_FAIL_ON_PATCH_ERROR

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
    libssl-dev \
    python3 \
    zlib1g-dev && \
  git clone "$CMANGOS_CORE_REPOSITORY_URL" /build/core && \
  git clone "$CMANGOS_PLAYERBOTS_REPOSITORY_URL" /build/playerbots && \
  cd /build/core && \
  git checkout "$CMANGOS_CORE_REVISION" && \
  cd /build/playerbots && \
  git checkout "$CMANGOS_PLAYERBOTS_REVISION" && \
  mkdir -p /build/core/src/modules && \
  cp -a /build/playerbots /build/core/src/modules/PlayerBots && \
  cd /build/core && \
  if [ -n "$CMANGOS_PATCHES_REPOSITORY_URL" ]; then \
    echo "Cloning and applying patches from $CMANGOS_PATCHES_REPOSITORY_URL"; \
    git clone "$CMANGOS_PATCHES_REPOSITORY_URL" /build/patches && \
    patch_count=0 && \
    # Patches in `all/` (and per-repo subdirectories under `all/`) are applied
    # to every expansion; patches in `<expansion>/` (and per-repo
    # subdirectories there) only to that expansion. Top-level `*.patch` files
    # apply to `/build/core`; `playerbots/*.patch` applies to
    # `/build/core/src/modules/PlayerBots`, which is the in-tree copy `mangosd`
    # actually compiles against (the build does not use `/build/playerbots`
    # directly). `database/*.patch` files exist for the database image only and
    # are not applied here.
    # The expansion-specific and per-repo subdirectories are optional and may
    # not exist.
    for patch in \
      /build/patches/all/*.patch \
      /build/patches/$CMANGOS_EXPANSION/*.patch \
      /build/patches/all/playerbots/*.patch \
      /build/patches/$CMANGOS_EXPANSION/playerbots/*.patch; \
    do \
      if [ -f "$patch" ]; then \
        case "$patch" in \
          */playerbots/*) target=/build/core/src/modules/PlayerBots ;; \
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
  mkdir -p \
    /opt/cmangos/config \
    /opt/cmangos/storage/client-data \
    /opt/cmangos/storage/data \
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
    -DBUILD_PLAYERBOTS=ON && \
  cmake --build . -j"$(nproc)" && \
  cmake --install .

FROM ubuntu:26.04

ARG TARGETARCH
ARG DEBIAN_FRONTEND
ARG CMANGOS_EXPANSION
ARG CMANGOS_USER_ID
ARG CMANGOS_GROUP_ID
ARG CMANGOS_USER_NAME
ARG CMANGOS_GROUP_NAME

# Force the Python stdout and stderr streams to be unbuffered so we can see the
# output from extractor scripts while they are running.
ENV PYTHONUNBUFFERED=1
ENV CMANGOS_EXPANSION=$CMANGOS_EXPANSION

RUN \
  apt update && \
  apt install -y --no-install-recommends \
    ca-certificates \
    curl \
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
    python3 \
    zlib1g && \
  # The Ubuntu 26.04 LTS Docker image has a user called `ubuntu` with UID 1000
  # and GID 1000 by default. Since we allow configuration of the name, UID and
  # GID of the user and group that should be used in the container, we need to
  # either rename the existing user and group or create a new user and group
  # with the specified name, UID and GID.
  cd /tmp && \
  existing_group=$(getent group "$CMANGOS_GROUP_ID") || true && \
  existing_user=$(getent passwd "$CMANGOS_USER_ID") || true && \
  if [ -n "$existing_group" ]; then \
    old_groupname=$(echo "$existing_group" | cut -d':' -f1) && \
    groupmod -n "$CMANGOS_GROUP_NAME" "$old_groupname"; \
  else \
    groupadd -g "$CMANGOS_GROUP_ID" "$CMANGOS_GROUP_NAME"; \
  fi && \
  if [ -n "$existing_user" ]; then \
    old_username=$(echo "$existing_user" | cut -d':' -f1) && \
    usermod -l "$CMANGOS_USER_NAME" -d "/home/$CMANGOS_USER_NAME" "$old_username" && \
    mv "/home/$old_username" "/home/$CMANGOS_USER_NAME"; \
  else \
    useradd -u "$CMANGOS_USER_ID" -g "$CMANGOS_GROUP_NAME" -d "/home/$CMANGOS_USER_NAME" -s /bin/sh -m "$CMANGOS_USER_NAME"; \
  fi && \
  # See https://github.com/boxboat/fixuid
  curl -SsL "https://github.com/boxboat/fixuid/releases/download/v0.6.0/fixuid-0.6.0-linux-$TARGETARCH.tar.gz" | tar -C /usr/local/bin -xzf - && \
  chown root:root /usr/local/bin/fixuid && \
  chmod 4755 /usr/local/bin/fixuid && \
  mkdir -p /etc/fixuid && \
  printf 'user: %s\ngroup: %s\n' "$CMANGOS_USER_NAME" "$CMANGOS_GROUP_NAME" > /etc/fixuid/config.yml && \
  apt remove -y curl && \
  apt autoremove -y && \
  apt clean -y && \
  rm -rf /var/lib/apt/lists/*

# `etc` holds the upstream-installed `*.conf.dist` files. They are not needed
# at runtime since `mangosd` is patched to read configuration files from
# `/opt/cmangos/config/` (the bind-mount target supplied by the user).
# `include`, `lib` and `share` may hold bundled fallback libraries CMaNGOS
# builds when the system lacks them, which our Docker image does not need.
COPY \
  --from=build \
  --exclude=cmangos/etc* \
  --exclude=cmangos/include* \
  --exclude=cmangos/lib* \
  --exclude=cmangos/share* \
  --chown=$CMANGOS_USER_NAME:$CMANGOS_GROUP_NAME \
  /opt /opt

COPY --chmod=755 ./docker/server/docker-cmd-mangosd.sh /usr/local/bin/mangosd
COPY --chmod=755 ./docker/server/docker-cmd-realmd.sh /usr/local/bin/realmd
COPY --chmod=755 ./docker/server/docker-cmd-extract-client-data.sh /usr/local/bin/extract-client-data

RUN \
  chmod +x /opt/cmangos/bin/* && \
  if [ -d /opt/cmangos/bin/tools ]; then \
    find /opt/cmangos/bin/tools -type f ! -name '*.txt' -exec chmod +x {} +; \
  fi

USER $CMANGOS_USER_NAME
WORKDIR "/home/$CMANGOS_USER_NAME"
CMD ["mangosd"]
