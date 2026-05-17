#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Resolves the previous database image's per-source commit hash for every
# expansion by reading the most recent combined revision tag from GHCR.
#
# Cutoff anchors below are the SHAs in each upstream source repo that
# cmangos-deploy was reviewed against initially. They are passed to
# `read-last-built-commit.sh` and used by it only when no prior image exists in
# the GitHub Container Registry to read a tag from; subsequent runs parse the
# previous image's combined revision tag instead.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env GH_TOKEN
require_env PACKAGE_OWNER
require_env CORE_REPOSITORY_OWNER
require_env DATABASE_REPOSITORY_OWNER
require_env PLAYERBOTS_REPOSITORY_OWNER
require_env PLAYERBOTS_REPOSITORY_NAME

CORE_CUTOFF_CLASSIC="1aea167db3494eb4fe9667227b886d2f662627f6"
CORE_CUTOFF_TBC="9eec6120a4a3098ed6d909e34334c9b0fb2ffb3b"
CORE_CUTOFF_WOTLK="fef8d93190482aaacf42f8831ae377bf7710925f"
DATABASE_CUTOFF_CLASSIC="2c980fa2175c9430b50fad644b2a4ef8204c4bb3"
DATABASE_CUTOFF_TBC="7d5224900b2cc484de5e06fa101965703ea27a0a"
DATABASE_CUTOFF_WOTLK="cb487b287aa1980aff157f8557999aeada505018"
PLAYERBOTS_CUTOFF="c33dfac220eb624761b6737324071ad7fae5b39f"

read_last_built() {
  local source="$1"
  local source_owner="$2"
  local source_name="$3"
  local package_name="$4"
  local cutoff="$5"
  local tmp_output

  tmp_output="$(mktemp)"
  GH_TOKEN="$GH_TOKEN" \
    PACKAGE_OWNER="$PACKAGE_OWNER" \
    PACKAGE_NAME="$package_name" \
    SOURCE="$source" \
    SOURCE_REPOSITORY_OWNER="$source_owner" \
    SOURCE_REPOSITORY_NAME="$source_name" \
    CUTOFF_COMMIT_HASH="$cutoff" \
    GITHUB_OUTPUT="$tmp_output" \
    "$script_dir/read-last-built-commit.sh" >&2

  sed -n 's/^commit_hash=//p' "$tmp_output"
  rm -f "$tmp_output"
}

result='{}'

for expansion in classic tbc wotlk; do
  case "$expansion" in
  classic)
    core_name="mangos-classic"
    db_name="classic-db"
    core_cutoff="$CORE_CUTOFF_CLASSIC"
    db_cutoff="$DATABASE_CUTOFF_CLASSIC"
    ;;
  tbc)
    core_name="mangos-tbc"
    db_name="tbc-db"
    core_cutoff="$CORE_CUTOFF_TBC"
    db_cutoff="$DATABASE_CUTOFF_TBC"
    ;;
  wotlk)
    core_name="mangos-wotlk"
    db_name="wotlk-db"
    core_cutoff="$CORE_CUTOFF_WOTLK"
    db_cutoff="$DATABASE_CUTOFF_WOTLK"
    ;;
  esac

  package_name="cmangos-database-$expansion"

  echo "Resolving last-built commits for '$expansion'..." >&2
  core_last_built="$(read_last_built \
    "core" "$CORE_REPOSITORY_OWNER" "$core_name" \
    "$package_name" "$core_cutoff")"
  database_last_built="$(read_last_built \
    "database" "$DATABASE_REPOSITORY_OWNER" "$db_name" \
    "$package_name" "$db_cutoff")"
  playerbots_last_built="$(read_last_built \
    "playerbots" "$PLAYERBOTS_REPOSITORY_OWNER" "$PLAYERBOTS_REPOSITORY_NAME" \
    "$package_name" "$PLAYERBOTS_CUTOFF")"

  result="$(jq \
    --arg expansion "$expansion" \
    --arg core "$core_last_built" \
    --arg database "$database_last_built" \
    --arg playerbots "$playerbots_last_built" \
    '. + {
       ($expansion): {
         core: $core,
         database: $database,
         playerbots: $playerbots
       }
     }' <<<"$result")"
done

write_output last_built_commits "$(jq -c '.' <<<"$result")"
