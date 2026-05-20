#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Resolves the upstream commit of each requested source to a full commit hash.
# Sources are opt-in: each one is resolved only when its matching environment
# variables are provided. The default workflow requests every source; the
# custom build workflow requests only the MariaDB entrypoint, because the other
# sources' resolved commit hashes have no consumer in the custom workflow.
# Emits the resolved commit hashes as job outputs so downstream steps (drift
# check, build decision, image builds) all reference the same revision set even
# if a branch tip moves during the run.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env GH_TOKEN

resolved_any=false

if [[ -n "${CORE_REPOSITORY_OWNER:-}${CORE_REVISION:-}" ]]; then
  require_env CORE_REPOSITORY_OWNER
  require_env CORE_REVISION

  cmangos_classic_repository="$CORE_REPOSITORY_OWNER/mangos-classic"
  cmangos_classic_commit_hash="$(resolve_commit_hash \
    "$CORE_REPOSITORY_OWNER" mangos-classic "$CORE_REVISION")"
  cmangos_tbc_repository="$CORE_REPOSITORY_OWNER/mangos-tbc"
  cmangos_tbc_commit_hash="$(resolve_commit_hash \
    "$CORE_REPOSITORY_OWNER" mangos-tbc "$CORE_REVISION")"
  cmangos_wotlk_repository="$CORE_REPOSITORY_OWNER/mangos-wotlk"
  cmangos_wotlk_commit_hash="$(resolve_commit_hash \
    "$CORE_REPOSITORY_OWNER" mangos-wotlk "$CORE_REVISION")"

  if [[ "$resolved_any" != "true" ]]; then printf 'Resolved sources:\n'; fi
  printf '  %s@%s\n' "$cmangos_classic_repository" "$cmangos_classic_commit_hash"
  printf '  %s@%s\n' "$cmangos_tbc_repository" "$cmangos_tbc_commit_hash"
  printf '  %s@%s\n' "$cmangos_wotlk_repository" "$cmangos_wotlk_commit_hash"

  write_output cmangos_classic_repository "$cmangos_classic_repository"
  write_output cmangos_classic_commit_hash "$cmangos_classic_commit_hash"
  write_output cmangos_tbc_repository "$cmangos_tbc_repository"
  write_output cmangos_tbc_commit_hash "$cmangos_tbc_commit_hash"
  write_output cmangos_wotlk_repository "$cmangos_wotlk_repository"
  write_output cmangos_wotlk_commit_hash "$cmangos_wotlk_commit_hash"
  resolved_any=true
fi

if [[ -n "${DATABASE_REPOSITORY_OWNER:-}${DATABASE_REVISION:-}" ]]; then
  require_env DATABASE_REPOSITORY_OWNER
  require_env DATABASE_REVISION

  classic_db_repository="$DATABASE_REPOSITORY_OWNER/classic-db"
  classic_db_commit_hash="$(resolve_commit_hash \
    "$DATABASE_REPOSITORY_OWNER" classic-db "$DATABASE_REVISION")"
  tbc_db_repository="$DATABASE_REPOSITORY_OWNER/tbc-db"
  tbc_db_commit_hash="$(resolve_commit_hash \
    "$DATABASE_REPOSITORY_OWNER" tbc-db "$DATABASE_REVISION")"
  wotlk_db_repository="$DATABASE_REPOSITORY_OWNER/wotlk-db"
  wotlk_db_commit_hash="$(resolve_commit_hash \
    "$DATABASE_REPOSITORY_OWNER" wotlk-db "$DATABASE_REVISION")"

  if [[ "$resolved_any" != "true" ]]; then printf 'Resolved sources:\n'; fi
  printf '  %s@%s\n' "$classic_db_repository" "$classic_db_commit_hash"
  printf '  %s@%s\n' "$tbc_db_repository" "$tbc_db_commit_hash"
  printf '  %s@%s\n' "$wotlk_db_repository" "$wotlk_db_commit_hash"

  write_output classic_db_repository "$classic_db_repository"
  write_output classic_db_commit_hash "$classic_db_commit_hash"
  write_output tbc_db_repository "$tbc_db_repository"
  write_output tbc_db_commit_hash "$tbc_db_commit_hash"
  write_output wotlk_db_repository "$wotlk_db_repository"
  write_output wotlk_db_commit_hash "$wotlk_db_commit_hash"
  resolved_any=true
fi

if [[ -n "${PLAYERBOTS_REPOSITORY_OWNER:-}${PLAYERBOTS_REPOSITORY_NAME:-}${PLAYERBOTS_REVISION:-}" ]]; then
  require_env PLAYERBOTS_REPOSITORY_OWNER
  require_env PLAYERBOTS_REPOSITORY_NAME
  require_env PLAYERBOTS_REVISION

  playerbots_repository="$PLAYERBOTS_REPOSITORY_OWNER/$PLAYERBOTS_REPOSITORY_NAME"
  playerbots_commit_hash="$(resolve_commit_hash \
    "$PLAYERBOTS_REPOSITORY_OWNER" "$PLAYERBOTS_REPOSITORY_NAME" \
    "$PLAYERBOTS_REVISION")"
  if [[ "$resolved_any" != "true" ]]; then printf 'Resolved sources:\n'; fi
  printf '  %s@%s\n' "$playerbots_repository" "$playerbots_commit_hash"

  write_output playerbots_repository "$playerbots_repository"
  write_output playerbots_commit_hash "$playerbots_commit_hash"
  resolved_any=true
fi

if [[ -n "${MARIADB_DOCKER_REPOSITORY_OWNER:-}${MARIADB_DOCKER_REPOSITORY_NAME:-}${MARIADB_DOCKER_REVISION:-}" ]]; then
  require_env MARIADB_DOCKER_REPOSITORY_OWNER
  require_env MARIADB_DOCKER_REPOSITORY_NAME
  require_env MARIADB_DOCKER_REVISION

  mariadb_docker_repository="$MARIADB_DOCKER_REPOSITORY_OWNER/$MARIADB_DOCKER_REPOSITORY_NAME"
  mariadb_docker_commit_hash="$(resolve_commit_hash \
    "$MARIADB_DOCKER_REPOSITORY_OWNER" "$MARIADB_DOCKER_REPOSITORY_NAME" \
    "$MARIADB_DOCKER_REVISION")"
  if [[ "$resolved_any" != "true" ]]; then printf 'Resolved sources:\n'; fi
  printf '  %s@%s\n' "$mariadb_docker_repository" "$mariadb_docker_commit_hash"

  write_output mariadb_docker_repository "$mariadb_docker_repository"
  write_output mariadb_docker_commit_hash "$mariadb_docker_commit_hash"
  resolved_any=true
fi

if [[ "$resolved_any" != "true" ]]; then
  fail "No sources requested; provide environment variables for at least one source."
fi
