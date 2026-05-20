#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Compares pinned upstream references against the resolved upstream `HEAD`.
# Sources are opt-in: each source's checks run only when its environment
# variables (`*_REPOSITORY`, `*_LATEST_COMMIT_HASH`, `*_KNOWN_COMMIT_HASH`) are
# provided. Fails the workflow when any reference has drifted so the matching
# local files can be reviewed.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# Each entry: <description>|<known_url>|<latest_url>.
declare -a checks=()

add_github_check() {
  local owner_repo="$1"
  local known_commit_hash="$2"
  local latest_commit_hash="$3"
  local path="$4"

  local desc="$owner_repo:$path"
  local known_url="https://raw.githubusercontent.com/$owner_repo/$known_commit_hash/$path"
  local latest_url="https://raw.githubusercontent.com/$owner_repo/$latest_commit_hash/$path"

  checks+=("$desc|$known_url|$latest_url")
}

# Files we ship for every expansion (configs we mirror as `*.conf.example` and
# the top-level `CMakeLists.txt`, which is where new `find_package(...)` would
# typically introduce a new dependency that we would need to install).
per_expansion_paths=(
  src/mangosd/mangosd.conf.dist.in
  src/realmd/realmd.conf.dist.in
  src/game/AuctionHouseBot/ahbot.conf.dist.in
  src/game/Anticheat/module/anticheat.conf.dist.in
  CMakeLists.txt
)

if [[ -n "${CMANGOS_CLASSIC_REPOSITORY:-}${CMANGOS_CLASSIC_LATEST_COMMIT_HASH:-}${CMANGOS_CLASSIC_KNOWN_COMMIT_HASH:-}" ]]; then
  require_env CMANGOS_CLASSIC_REPOSITORY
  require_env CMANGOS_CLASSIC_LATEST_COMMIT_HASH
  require_env CMANGOS_CLASSIC_KNOWN_COMMIT_HASH

  # shellcheck disable=SC2153
  cmangos_classic_latest_commit_hash="$(trim "$CMANGOS_CLASSIC_LATEST_COMMIT_HASH")"

  for path in "${per_expansion_paths[@]}"; do
    add_github_check "$CMANGOS_CLASSIC_REPOSITORY" \
      "$CMANGOS_CLASSIC_KNOWN_COMMIT_HASH" "$cmangos_classic_latest_commit_hash" "$path"
  done

  # `mods.conf` only ships for Classic upstream; the file does not exist for
  # TBC/WotLK.
  add_github_check "$CMANGOS_CLASSIC_REPOSITORY" \
    "$CMANGOS_CLASSIC_KNOWN_COMMIT_HASH" "$cmangos_classic_latest_commit_hash" \
    src/mangosd/mods.conf.dist.in
fi

if [[ -n "${CMANGOS_TBC_REPOSITORY:-}${CMANGOS_TBC_LATEST_COMMIT_HASH:-}${CMANGOS_TBC_KNOWN_COMMIT_HASH:-}" ]]; then
  require_env CMANGOS_TBC_REPOSITORY
  require_env CMANGOS_TBC_LATEST_COMMIT_HASH
  require_env CMANGOS_TBC_KNOWN_COMMIT_HASH

  # shellcheck disable=SC2153
  cmangos_tbc_latest_commit_hash="$(trim "$CMANGOS_TBC_LATEST_COMMIT_HASH")"

  for path in "${per_expansion_paths[@]}"; do
    add_github_check "$CMANGOS_TBC_REPOSITORY" \
      "$CMANGOS_TBC_KNOWN_COMMIT_HASH" "$cmangos_tbc_latest_commit_hash" "$path"
  done
fi

if [[ -n "${CMANGOS_WOTLK_REPOSITORY:-}${CMANGOS_WOTLK_LATEST_COMMIT_HASH:-}${CMANGOS_WOTLK_KNOWN_COMMIT_HASH:-}" ]]; then
  require_env CMANGOS_WOTLK_REPOSITORY
  require_env CMANGOS_WOTLK_LATEST_COMMIT_HASH
  require_env CMANGOS_WOTLK_KNOWN_COMMIT_HASH

  # shellcheck disable=SC2153
  cmangos_wotlk_latest_commit_hash="$(trim "$CMANGOS_WOTLK_LATEST_COMMIT_HASH")"

  for path in "${per_expansion_paths[@]}"; do
    add_github_check "$CMANGOS_WOTLK_REPOSITORY" \
      "$CMANGOS_WOTLK_KNOWN_COMMIT_HASH" "$cmangos_wotlk_latest_commit_hash" "$path"
  done
fi

# Per-expansion `InstallFullDB.sh`. Our `docker/database/db-functions.sh`
# re-implements its install + update flow, so upstream changes here may need to
# be mirrored into our re-implementation.
if [[ -n "${CLASSIC_DB_REPOSITORY:-}${CLASSIC_DB_LATEST_COMMIT_HASH:-}${CLASSIC_DB_KNOWN_COMMIT_HASH:-}" ]]; then
  require_env CLASSIC_DB_REPOSITORY
  require_env CLASSIC_DB_LATEST_COMMIT_HASH
  require_env CLASSIC_DB_KNOWN_COMMIT_HASH

  # shellcheck disable=SC2153
  classic_db_latest_commit_hash="$(trim "$CLASSIC_DB_LATEST_COMMIT_HASH")"

  add_github_check "$CLASSIC_DB_REPOSITORY" \
    "$CLASSIC_DB_KNOWN_COMMIT_HASH" "$classic_db_latest_commit_hash" InstallFullDB.sh
fi

if [[ -n "${TBC_DB_REPOSITORY:-}${TBC_DB_LATEST_COMMIT_HASH:-}${TBC_DB_KNOWN_COMMIT_HASH:-}" ]]; then
  require_env TBC_DB_REPOSITORY
  require_env TBC_DB_LATEST_COMMIT_HASH
  require_env TBC_DB_KNOWN_COMMIT_HASH

  # shellcheck disable=SC2153
  tbc_db_latest_commit_hash="$(trim "$TBC_DB_LATEST_COMMIT_HASH")"

  add_github_check "$TBC_DB_REPOSITORY" \
    "$TBC_DB_KNOWN_COMMIT_HASH" "$tbc_db_latest_commit_hash" InstallFullDB.sh
fi

if [[ -n "${WOTLK_DB_REPOSITORY:-}${WOTLK_DB_LATEST_COMMIT_HASH:-}${WOTLK_DB_KNOWN_COMMIT_HASH:-}" ]]; then
  require_env WOTLK_DB_REPOSITORY
  require_env WOTLK_DB_LATEST_COMMIT_HASH
  require_env WOTLK_DB_KNOWN_COMMIT_HASH

  # shellcheck disable=SC2153
  wotlk_db_latest_commit_hash="$(trim "$WOTLK_DB_LATEST_COMMIT_HASH")"

  add_github_check "$WOTLK_DB_REPOSITORY" \
    "$WOTLK_DB_KNOWN_COMMIT_HASH" "$wotlk_db_latest_commit_hash" InstallFullDB.sh
fi

if [[ -n "${PLAYERBOTS_REPOSITORY:-}${PLAYERBOTS_LATEST_COMMIT_HASH:-}${PLAYERBOTS_KNOWN_COMMIT_HASH:-}" ]]; then
  require_env PLAYERBOTS_REPOSITORY
  require_env PLAYERBOTS_LATEST_COMMIT_HASH
  require_env PLAYERBOTS_KNOWN_COMMIT_HASH

  # shellcheck disable=SC2153
  playerbots_latest_commit_hash="$(trim "$PLAYERBOTS_LATEST_COMMIT_HASH")"

  # Playerbots ships an expansion-specific suffix on the same template name.
  add_github_check "$PLAYERBOTS_REPOSITORY" \
    "$PLAYERBOTS_KNOWN_COMMIT_HASH" "$playerbots_latest_commit_hash" \
    playerbot/aiplayerbot.conf.dist.in
  add_github_check "$PLAYERBOTS_REPOSITORY" \
    "$PLAYERBOTS_KNOWN_COMMIT_HASH" "$playerbots_latest_commit_hash" \
    playerbot/aiplayerbot.conf.dist.in.tbc
  add_github_check "$PLAYERBOTS_REPOSITORY" \
    "$PLAYERBOTS_KNOWN_COMMIT_HASH" "$playerbots_latest_commit_hash" \
    playerbot/aiplayerbot.conf.dist.in.wotlk
fi

if [[ -n "${MARIADB_DOCKER_REPOSITORY:-}${MARIADB_DOCKER_LATEST_COMMIT_HASH:-}${MARIADB_DOCKER_KNOWN_COMMIT_HASH:-}" ]]; then
  require_env MARIADB_DOCKER_REPOSITORY
  require_env MARIADB_DOCKER_LATEST_COMMIT_HASH
  require_env MARIADB_DOCKER_KNOWN_COMMIT_HASH

  # shellcheck disable=SC2153
  mariadb_docker_latest_commit_hash="$(trim "$MARIADB_DOCKER_LATEST_COMMIT_HASH")"

  # Patched MariaDB entrypoint. Our `docker/database/docker-entrypoint.sh`
  # extends functions defined in upstream's version, so any change there has to
  # be reviewed for compatibility.
  add_github_check "$MARIADB_DOCKER_REPOSITORY" \
    "$MARIADB_DOCKER_KNOWN_COMMIT_HASH" "$mariadb_docker_latest_commit_hash" \
    11.8/docker-entrypoint.sh
fi

if ((${#checks[@]} == 0)); then
  fail "No drift checks requested; provide environment variables for at least one source."
fi

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
  fail "Review the diff(s) above, refresh any local files that need to align, and bump the matching *_KNOWN_COMMIT_HASH."
fi
