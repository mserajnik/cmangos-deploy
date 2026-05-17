#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Compares pinned upstream references (the MariaDB entrypoint, CMaNGOS files we
# mirror) against current upstream `HEAD`. Fails the workflow when any has
# drifted so the matching local copy can be reviewed.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env MARIADB_DOCKER_KNOWN_SHA
require_env CMANGOS_CLASSIC_KNOWN_SHA
require_env CMANGOS_TBC_KNOWN_SHA
require_env CMANGOS_WOTLK_KNOWN_SHA
require_env CLASSIC_DB_KNOWN_SHA
require_env TBC_DB_KNOWN_SHA
require_env WOTLK_DB_KNOWN_SHA
require_env PLAYERBOTS_KNOWN_SHA

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# Each entry: <description>|<known_url>|<latest_url>.
declare -a checks=()

add_github_check() {
  local owner_repo="$1"
  local ref="$2"
  local latest_ref="$3"
  local path="$4"

  local desc="$owner_repo:$path"
  local known_url="https://raw.githubusercontent.com/$owner_repo/$ref/$path"
  local latest_url="https://raw.githubusercontent.com/$owner_repo/$latest_ref/$path"

  checks+=("$desc|$known_url|$latest_url")
}

# Patched MariaDB entrypoint. The cmangos-deploy
# `docker/database/docker-entrypoint.sh` extends functions defined in
# upstream's version, so any change there has to be reviewed for compatibility.
add_github_check MariaDB/mariadb-docker "$MARIADB_DOCKER_KNOWN_SHA" master \
  11.8/docker-entrypoint.sh

# Files we ship for every expansion (configs we mirror as `*.conf.example` and
# the top-level `CMakeLists.txt`, which is where new `find_package(...)` would
# typically introduce a new apt dep that `docker/server/Dockerfile` would need
# to install).
per_expansion_paths=(
  src/mangosd/mangosd.conf.dist.in
  src/realmd/realmd.conf.dist.in
  src/game/AuctionHouseBot/ahbot.conf.dist.in
  src/game/Anticheat/module/anticheat.conf.dist.in
  CMakeLists.txt
)

for path in "${per_expansion_paths[@]}"; do
  add_github_check cmangos/mangos-classic "$CMANGOS_CLASSIC_KNOWN_SHA" master "$path"
  add_github_check cmangos/mangos-tbc "$CMANGOS_TBC_KNOWN_SHA" master "$path"
  add_github_check cmangos/mangos-wotlk "$CMANGOS_WOTLK_KNOWN_SHA" master "$path"
done

# `mods.conf` only ships for Classic upstream; the file does not exist for
# TBC/WotLK.
add_github_check cmangos/mangos-classic "$CMANGOS_CLASSIC_KNOWN_SHA" master \
  src/mangosd/mods.conf.dist.in

# Upstream's DB install/update script per expansion. Our `db-functions.sh`
# re-implements its install + update flow, so any change here may need to be
# mirrored into our re-implementation.
add_github_check cmangos/classic-db "$CLASSIC_DB_KNOWN_SHA" master InstallFullDB.sh
add_github_check cmangos/tbc-db "$TBC_DB_KNOWN_SHA" master InstallFullDB.sh
add_github_check cmangos/wotlk-db "$WOTLK_DB_KNOWN_SHA" master InstallFullDB.sh

# Playerbots ships an expansion-specific suffix on the same template name.
add_github_check cmangos/playerbots "$PLAYERBOTS_KNOWN_SHA" master \
  playerbot/aiplayerbot.conf.dist.in
add_github_check cmangos/playerbots "$PLAYERBOTS_KNOWN_SHA" master \
  playerbot/aiplayerbot.conf.dist.in.tbc
add_github_check cmangos/playerbots "$PLAYERBOTS_KNOWN_SHA" master \
  playerbot/aiplayerbot.conf.dist.in.wotlk

failures=0

for check in "${checks[@]}"; do
  IFS='|' read -r desc known_url latest_url <<<"$check"

  curl --fail --silent --show-error --location \
    --output "$workdir/known" "$known_url"
  curl --fail --silent --show-error --location \
    --output "$workdir/latest" "$latest_url"

  if ! diff -u "$workdir/known" "$workdir/latest" >/dev/null; then
    printf '\n=== DRIFT DETECTED: %s ===\n' "$desc"
    diff -u "$workdir/known" "$workdir/latest" || true
    failures=$((failures + 1))
  else
    printf 'OK: %s\n' "$desc"
  fi
done

if ((failures > 0)); then
  printf '\n%s upstream reference(s) drifted from the pinned revision.\n' "$failures" >&2
  fail "Review the diff(s) above, refresh any local files that need to align, and bump the matching *_KNOWN_SHA."
fi
