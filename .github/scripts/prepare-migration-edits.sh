#!/usr/bin/env bash

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

# Invokes `compute-migration-edits.sh` for each expansion (classic, tbc, wotlk)
# and emits the resulting build arguments as a single JSON output keyed by
# expansion.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env GH_TOKEN
require_env BUILD_METADATA
require_env LAST_BUILT_COMMITS
require_env CORE_REPOSITORY_OWNER
require_env DATABASE_REPOSITORY_OWNER
require_env PLAYERBOTS_REPOSITORY_OWNER
require_env PLAYERBOTS_REPOSITORY_NAME

migration_edits='{}'

for expansion in classic tbc wotlk; do
  case "$expansion" in
  classic)
    core_name="mangos-classic"
    db_name="classic-db"
    ;;
  tbc)
    core_name="mangos-tbc"
    db_name="tbc-db"
    ;;
  wotlk)
    core_name="mangos-wotlk"
    db_name="wotlk-db"
    ;;
  esac

  state_file=".github/migration-edit-state-$expansion.json"

  core_current="$(jq -r --arg e "$expansion" '.[$e].core_commit_hash' <<<"$BUILD_METADATA")"
  db_current="$(jq -r --arg e "$expansion" '.[$e].database_commit_hash' <<<"$BUILD_METADATA")"
  playerbots_current="$(jq -r --arg e "$expansion" '.[$e].playerbots_commit_hash' <<<"$BUILD_METADATA")"

  core_last_built="$(jq -r --arg e "$expansion" '.[$e].core' <<<"$LAST_BUILT_COMMITS")"
  database_last_built="$(jq -r --arg e "$expansion" '.[$e].database' <<<"$LAST_BUILT_COMMITS")"
  playerbots_last_built="$(jq -r --arg e "$expansion" '.[$e].playerbots' <<<"$LAST_BUILT_COMMITS")"

  echo "Computing migration edits for '$expansion'..."
  GH_TOKEN="$GH_TOKEN" \
    STATE_FILE="$state_file" \
    EXPANSION="$expansion" \
    CORE_REPOSITORY_OWNER="$CORE_REPOSITORY_OWNER" \
    CORE_REPOSITORY_NAME="$core_name" \
    CORE_LAST_BUILT_COMMIT_HASH="$core_last_built" \
    CORE_CURRENT_COMMIT_HASH="$core_current" \
    DATABASE_REPOSITORY_OWNER="$DATABASE_REPOSITORY_OWNER" \
    DATABASE_REPOSITORY_NAME="$db_name" \
    DATABASE_LAST_BUILT_COMMIT_HASH="$database_last_built" \
    DATABASE_CURRENT_COMMIT_HASH="$db_current" \
    PLAYERBOTS_REPOSITORY_OWNER="$PLAYERBOTS_REPOSITORY_OWNER" \
    PLAYERBOTS_REPOSITORY_NAME="$PLAYERBOTS_REPOSITORY_NAME" \
    PLAYERBOTS_LAST_BUILT_COMMIT_HASH="$playerbots_last_built" \
    PLAYERBOTS_CURRENT_COMMIT_HASH="$playerbots_current" \
    "$script_dir/compute-migration-edits.sh"

  arg="$("$script_dir/migration-edits-to-arg.sh" "$state_file")"
  migration_edits="$(jq -c \
    --arg expansion "$expansion" \
    --arg arg "$arg" \
    '. + {($expansion): $arg}' <<<"$migration_edits")"
done

write_output migration_edits "$migration_edits"
