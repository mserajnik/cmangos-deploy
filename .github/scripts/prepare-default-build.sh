#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Decides whether the default workflow should build images this run (skipping
# when images for the resolved per-expansion commits already exist, unless the
# run is a scheduled Monday rebuild or a manual force rebuild). Consumes the
# commit hashes resolved by `resolve-sources.sh` and emits the per-expansion
# build metadata downstream image-build jobs consume.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env GH_TOKEN
require_env GITHUB_EVENT_NAME
require_env PACKAGE_OWNER
require_env PACKAGE_NAME_PREFIX
require_env CORE_REPOSITORY_OWNER
require_env DATABASE_REPOSITORY_OWNER
require_env PLAYERBOTS_REPOSITORY_OWNER
require_env PLAYERBOTS_REPOSITORY_NAME
require_env CMANGOS_CLASSIC_COMMIT_HASH
require_env CMANGOS_TBC_COMMIT_HASH
require_env CMANGOS_WOTLK_COMMIT_HASH
require_env CLASSIC_DB_COMMIT_HASH
require_env TBC_DB_COMMIT_HASH
require_env WOTLK_DB_COMMIT_HASH
require_env PLAYERBOTS_COMMIT_HASH

force_rebuild="${FORCE_REBUILD:-false}"
schedule_force_build="false"

if [[ "$GITHUB_EVENT_NAME" == "schedule" && "$(date +%u)" -eq 1 ]]; then
  schedule_force_build="true"
fi

declare -a expansions=(classic tbc wotlk)

# Per-expansion repository names and resolved commit hashes; everything else
# (owner, package name prefix) is shared across expansions and surfaced via
# environment variables from the workflow.
declare -A core_repository_name=(
  [classic]=mangos-classic
  [tbc]=mangos-tbc
  [wotlk]=mangos-wotlk
)
declare -A database_repository_name=(
  [classic]=classic-db
  [tbc]=tbc-db
  [wotlk]=wotlk-db
)
# shellcheck disable=SC2153
declare -A core_commit_hash_by_expansion=(
  [classic]="$(trim "$CMANGOS_CLASSIC_COMMIT_HASH")"
  [tbc]="$(trim "$CMANGOS_TBC_COMMIT_HASH")"
  [wotlk]="$(trim "$CMANGOS_WOTLK_COMMIT_HASH")"
)
# shellcheck disable=SC2153
declare -A database_commit_hash_by_expansion=(
  [classic]="$(trim "$CLASSIC_DB_COMMIT_HASH")"
  [tbc]="$(trim "$TBC_DB_COMMIT_HASH")"
  [wotlk]="$(trim "$WOTLK_DB_COMMIT_HASH")"
)

# shellcheck disable=SC2153
playerbots_commit_hash="$(trim "$PLAYERBOTS_COMMIT_HASH")"

build_metadata="{}"
declare -a expansions_to_build=()
any_images_to_build="false"

for expansion in "${expansions[@]}"; do
  core_name="${core_repository_name[$expansion]}"
  database_name="${database_repository_name[$expansion]}"

  core_url="https://github.com/$CORE_REPOSITORY_OWNER/$core_name.git"
  database_url="https://github.com/$DATABASE_REPOSITORY_OWNER/$database_name.git"
  playerbots_url="https://github.com/$PLAYERBOTS_REPOSITORY_OWNER/$PLAYERBOTS_REPOSITORY_NAME.git"

  core_commit_hash="${core_commit_hash_by_expansion[$expansion]}"
  database_commit_hash="${database_commit_hash_by_expansion[$expansion]}"

  combined_revision_tag="$expansion"
  combined_revision_tag+="-core.$(short_revision "$core_commit_hash")"
  combined_revision_tag+="-db.$(short_revision "$database_commit_hash")"
  combined_revision_tag+="-playerbots.$(short_revision "$playerbots_commit_hash")"

  images_already_exist="false"

  if [[ "$schedule_force_build" == "true" || "$force_rebuild" == "true" ]]; then
    images_already_exist="false"
  else
    # shellcheck disable=SC2153
    existing_tags="$(existing_tags_for_package "$PACKAGE_OWNER" "$PACKAGE_NAME_PREFIX-$expansion")"

    if grep -Fxq "$combined_revision_tag" <<<"$existing_tags"; then
      images_already_exist="true"
    fi
  fi

  if [[ "$images_already_exist" != "true" ]]; then
    any_images_to_build="true"
    expansions_to_build+=("$expansion")
  fi

  build_metadata="$(jq \
    --arg expansion "$expansion" \
    --arg core_repository_url "$core_url" \
    --arg core_commit_hash "$core_commit_hash" \
    --arg database_repository_url "$database_url" \
    --arg database_commit_hash "$database_commit_hash" \
    --arg playerbots_repository_url "$playerbots_url" \
    --arg playerbots_commit_hash "$playerbots_commit_hash" \
    --arg combined_revision_tag "$combined_revision_tag" \
    --arg images_already_exist "$images_already_exist" \
    '. + {
       ($expansion): {
         core_repository_url: $core_repository_url,
         core_commit_hash: $core_commit_hash,
         database_repository_url: $database_repository_url,
         database_commit_hash: $database_commit_hash,
         playerbots_repository_url: $playerbots_repository_url,
         playerbots_commit_hash: $playerbots_commit_hash,
         combined_revision_tag: $combined_revision_tag,
         images_already_exist: $images_already_exist
       }
     }' <<<"$build_metadata")"
done

if ((${#expansions_to_build[@]} > 0)); then
  expansions_to_build_json="$(printf '%s\n' "${expansions_to_build[@]}" | jq -R . | jq -s -c .)"
else
  expansions_to_build_json="[]"
fi

write_output build_metadata "$(jq -c '.' <<<"$build_metadata")"
write_output expansions_to_build "$expansions_to_build_json"
write_output any_images_to_build "$any_images_to_build"
