#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Resolves the current upstream CMaNGOS commits for each expansion (core,
# database, and Playerbots) and decides whether the default workflow should
# build images this run (skipping when images for those commits already exist,
# unless the run is a scheduled Monday rebuild or a manual force rebuild).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env GH_TOKEN
require_env GITHUB_EVENT_NAME
require_env PACKAGE_OWNER
require_env PACKAGE_NAME_PREFIX
require_env CORE_REPOSITORY_OWNER
require_env CORE_REPOSITORY_REVISION
require_env DATABASE_REPOSITORY_OWNER
require_env DATABASE_REPOSITORY_REVISION
require_env PLAYERBOTS_REPOSITORY_OWNER
require_env PLAYERBOTS_REPOSITORY_NAME
require_env PLAYERBOTS_REPOSITORY_REVISION

force_rebuild="${FORCE_REBUILD:-false}"
schedule_force_build="false"

if [[ "$GITHUB_EVENT_NAME" == "schedule" && "$(date +%u)" -eq 1 ]]; then
  schedule_force_build="true"
fi

resolve_commit_hash() {
  local repository_owner="$1"
  local repository_name="$2"
  local repository_ref="$3"

  gh api "/repos/$repository_owner/$repository_name/commits/$repository_ref" \
    --jq '.sha'
}

existing_tags_for_package() {
  local package_owner="$1"
  local package_name="$2"
  local endpoint
  local tags
  local status

  endpoint="$(package_versions_endpoint "$package_owner" "$package_name")"

  set +e
  tags="$(gh api --paginate "$endpoint?per_page=100" \
    --jq '.[].metadata.container.tags[]?' 2>&1)"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    if grep -Fq "HTTP 404" <<<"$tags"; then
      printf '%s' ""
      return 0
    fi

    printf '%s\n' "$tags" >&2
    fail "Failed to query package versions for '$package_owner/$package_name'."
  fi

  printf '%s' "$tags"
}

declare -a expansions=(classic tbc wotlk)

# Only the per-expansion repository names actually vary; everything else
# (owner, ref, package name prefix) is shared across expansions and surfaced
# via env vars from the workflow.
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

build_metadata="{}"
declare -a expansions_to_build=()
any_images_to_build="false"

for expansion in "${expansions[@]}"; do
  core_name="${core_repository_name[$expansion]}"
  database_name="${database_repository_name[$expansion]}"

  core_url="https://github.com/$CORE_REPOSITORY_OWNER/$core_name.git"
  database_url="https://github.com/$DATABASE_REPOSITORY_OWNER/$database_name.git"
  playerbots_url="https://github.com/$PLAYERBOTS_REPOSITORY_OWNER/$PLAYERBOTS_REPOSITORY_NAME.git"

  core_hash="$(resolve_commit_hash \
    "$CORE_REPOSITORY_OWNER" "$core_name" "$CORE_REPOSITORY_REVISION")"
  database_hash="$(resolve_commit_hash \
    "$DATABASE_REPOSITORY_OWNER" "$database_name" "$DATABASE_REPOSITORY_REVISION")"
  playerbots_hash="$(resolve_commit_hash \
    "$PLAYERBOTS_REPOSITORY_OWNER" "$PLAYERBOTS_REPOSITORY_NAME" "$PLAYERBOTS_REPOSITORY_REVISION")"

  combined_revision_tag="$expansion"
  combined_revision_tag+="-core.$(short_revision "$core_hash")"
  combined_revision_tag+="-db.$(short_revision "$database_hash")"
  combined_revision_tag+="-playerbots.$(short_revision "$playerbots_hash")"

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
    --arg core_commit_hash "$core_hash" \
    --arg database_repository_url "$database_url" \
    --arg database_commit_hash "$database_hash" \
    --arg playerbots_repository_url "$playerbots_url" \
    --arg playerbots_commit_hash "$playerbots_hash" \
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
