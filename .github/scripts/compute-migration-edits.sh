#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Walks the commits between the previous and current build for one expansion
# via the GitHub API and updates that expansion's migration edit state file
# with the most recent migration file edit per `(db, source)` pair.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env GH_TOKEN
require_env STATE_FILE
require_env EXPANSION
require_env CORE_REPOSITORY_OWNER
require_env CORE_REPOSITORY_NAME
require_env CORE_LAST_BUILT_COMMIT_HASH
require_env CORE_CURRENT_COMMIT_HASH
require_env DATABASE_REPOSITORY_OWNER
require_env DATABASE_REPOSITORY_NAME
require_env DATABASE_LAST_BUILT_COMMIT_HASH
require_env DATABASE_CURRENT_COMMIT_HASH
require_env PLAYERBOTS_REPOSITORY_OWNER
require_env PLAYERBOTS_REPOSITORY_NAME
require_env PLAYERBOTS_LAST_BUILT_COMMIT_HASH
require_env PLAYERBOTS_CURRENT_COMMIT_HASH

case "$EXPANSION" in
classic | tbc | wotlk) ;;
*)
  fail "Unsupported expansion '$EXPANSION'."
  ;;
esac

if [[ ! -f "$STATE_FILE" ]]; then
  fail "State file '$STATE_FILE' does not exist."
fi

# Parallel indexed arrays describe the seven walks. macOS Bash 3.2 has no
# associative arrays, so we keep these as positional lists.
#
# Each index `i` describes one walk:
#   walk_dbs[i]: the DB slot (world/characters/realmd/logs)
#   walk_sources[i]: the source slot under that DB (core/database/playerbots)
#   walk_owners[i]: the source repository's GitHub owner
#   walk_names[i]: the source repository's GitHub repo name
#   walk_bases[i]: the previous build's commit hash in that source repo
#   walk_heads[i]: the current build's commit hash in that source repo
#   walk_patterns[i]: a `|`-separated list of file-path regexes to match
walk_dbs=(world world world characters characters realmd logs)
walk_sources=(core database playerbots core playerbots core core)
walk_owners=(
  "$CORE_REPOSITORY_OWNER"
  "$DATABASE_REPOSITORY_OWNER"
  "$PLAYERBOTS_REPOSITORY_OWNER"
  "$CORE_REPOSITORY_OWNER"
  "$PLAYERBOTS_REPOSITORY_OWNER"
  "$CORE_REPOSITORY_OWNER"
  "$CORE_REPOSITORY_OWNER"
)
walk_names=(
  "$CORE_REPOSITORY_NAME"
  "$DATABASE_REPOSITORY_NAME"
  "$PLAYERBOTS_REPOSITORY_NAME"
  "$CORE_REPOSITORY_NAME"
  "$PLAYERBOTS_REPOSITORY_NAME"
  "$CORE_REPOSITORY_NAME"
  "$CORE_REPOSITORY_NAME"
)
walk_bases=(
  "$CORE_LAST_BUILT_COMMIT_HASH"
  "$DATABASE_LAST_BUILT_COMMIT_HASH"
  "$PLAYERBOTS_LAST_BUILT_COMMIT_HASH"
  "$CORE_LAST_BUILT_COMMIT_HASH"
  "$PLAYERBOTS_LAST_BUILT_COMMIT_HASH"
  "$CORE_LAST_BUILT_COMMIT_HASH"
  "$CORE_LAST_BUILT_COMMIT_HASH"
)
walk_heads=(
  "$CORE_CURRENT_COMMIT_HASH"
  "$DATABASE_CURRENT_COMMIT_HASH"
  "$PLAYERBOTS_CURRENT_COMMIT_HASH"
  "$CORE_CURRENT_COMMIT_HASH"
  "$PLAYERBOTS_CURRENT_COMMIT_HASH"
  "$CORE_CURRENT_COMMIT_HASH"
  "$CORE_CURRENT_COMMIT_HASH"
)
walk_patterns=(
  '^sql/base/mangos\.sql$|^sql/updates/mangos/[^/]+\.sql$|^sql/base/ahbot/[^/]+\.sql$|^sql/base/dbc/original_data/[^/]+\.sql$|^sql/base/dbc/cmangos_fixes/[^/]+\.sql$|^sql/scriptdev2/[^/]+\.sql$'
  '^Full_DB/[^/]+\.sql(\.gz)?$|^Updates/[^/]+\.sql$|^Updates/Instances/[^/]+\.sql$|^ACID/acid_'"$EXPANSION"'\.sql$|^utilities/cmangos_custom\.sql$|^locales/[^/]+\.sql$'
  '^sql/world/[^/]+\.sql$|^sql/world/'"$EXPANSION"'/[^/]+\.sql$'
  '^sql/base/characters\.sql$|^sql/updates/characters/[^/]+\.sql$'
  '^sql/characters/[^/]+\.sql$'
  '^sql/base/realmd\.sql$|^sql/updates/realmd/[^/]+\.sql$'
  '^sql/base/logs\.sql$|^sql/updates/logs/[^/]+\.sql$'
)

# Outputs filled by the walks below: same shape as the input arrays so an entry
# at index `i` corresponds to the `(walk_dbs[i], walk_sources[i])` pair.
found_commits=("" "" "" "" "" "" "")
found_subjects=("" "" "" "" "" "" "")

walk_one() {
  local idx="$1"

  local db="${walk_dbs[$idx]}"
  local source="${walk_sources[$idx]}"
  local owner="${walk_owners[$idx]}"
  local name="${walk_names[$idx]}"
  local base="${walk_bases[$idx]}"
  local head="${walk_heads[$idx]}"
  local pattern="${walk_patterns[$idx]}"
  local repo="$owner/$name"

  if [[ "$base" == "$head" ]]; then
    echo "[$db.$source] Last built and current commits in '$repo' are identical; skipping."
    return 0
  fi

  echo "[$db.$source] Scanning '$repo' between $base and $head..."

  local shas_oldest_first
  shas_oldest_first="$(gh api --paginate \
    "repos/$repo/compare/$base...$head" \
    --jq '.commits[].sha')"

  if [[ -z "$shas_oldest_first" ]]; then
    echo "[$db.$source] No commits between $base and $head."
    return 0
  fi

  local shas_newest_first
  shas_newest_first="$(tac <<<"$shas_oldest_first")"
  local total
  total="$(wc -l <<<"$shas_newest_first" | tr -d ' ')"
  echo "[$db.$source] Walking $total commits newest-first."

  local scanned=0
  local sha
  # Each iteration makes one `gh api ...commits/<sha>` call. The 5000 calls per
  # hour `GITHUB_TOKEN` rate limit bounds the worst case (~14 months of history
  # from the cutoff anchor on a fresh fork's first build).
  while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    scanned=$((scanned + 1))

    local commit_data
    commit_data="$(gh api "repos/$repo/commits/$sha")"

    # We skip merge commits because their diff against the first parent would
    # attribute the merged branch's file changes to the merge commit itself,
    # which would give us the wrong timestamp and subject.
    local parent_count
    parent_count="$(jq -r '.parents | length' <<<"$commit_data")"
    if [[ "$parent_count" -ne 1 ]]; then
      continue
    fi

    local files_json
    files_json="$(jq -c '.files' <<<"$commit_data")"
    local subject
    subject="$(jq -r '.commit.message | split("\n")[0]' <<<"$commit_data")"

    local has_edit
    has_edit="$(jq -r --arg pattern "$pattern" '
      [.[]
        | select(.status == "modified" or .status == "renamed" or .status == "removed")
        | select((.filename | test($pattern)) or ((.previous_filename // "") | test($pattern)))
      ] | length' <<<"$files_json")"

    if [[ "$has_edit" -gt 0 ]]; then
      found_commits[idx]="$sha"
      found_subjects[idx]="$subject"
      echo "[$db.$source] $sha ($subject)"
      break
    fi
  done <<<"$shas_newest_first"

  echo "[$db.$source] Scanned $scanned commit(s)."
}

for i in "${!walk_dbs[@]}"; do
  walk_one "$i"
done

# Rebuild the state file in deterministic shape: keep every (db, source) slot
# we know about, overlaying any new findings on top of the existing entries.
state_filter='
  {
    world: {
      core:       .world.core,
      database:   .world.database,
      playerbots: .world.playerbots
    },
    characters: {
      core:       .characters.core,
      playerbots: .characters.playerbots
    },
    realmd: { core: .realmd.core },
    logs:   { core: .logs.core }
  }
'
new_state="$(jq "$state_filter" "$STATE_FILE")"

any_updates="false"
for i in "${!walk_dbs[@]}"; do
  if [[ -n "${found_commits[$i]}" ]]; then
    any_updates="true"
    new_state="$(jq \
      --arg db "${walk_dbs[$i]}" \
      --arg source "${walk_sources[$i]}" \
      --arg sha "${found_commits[$i]}" \
      --arg subject "${found_subjects[$i]}" \
      '.[$db][$source] = {commit: $sha, subject: $subject}' \
      <<<"$new_state")"
  fi
done

if [[ "$any_updates" == "false" ]]; then
  echo "No new migration edits for '$EXPANSION'; state file unchanged."
  exit 0
fi

existing_state="$(<"$STATE_FILE")"
if [[ "$new_state" == "$existing_state" ]]; then
  echo "'$STATE_FILE' already up to date."
  exit 0
fi

printf '%s\n' "$new_state" >"$STATE_FILE"
echo "Updated '$STATE_FILE'."
