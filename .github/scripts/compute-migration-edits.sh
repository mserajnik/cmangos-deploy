#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Walks the commits between the previous and current build for one expansion
# and updates that expansion's migration edit state file with the most recent
# migration file edit per `(db, source)` pair.
#
# The walk reads a blobless clone rather than the GitHub API, whose commit
# endpoint silently caps a file list and could hide a watched file.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

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

# A state file `jq` cannot read as an object would make the writeback's
# comparison read as "already up to date" and silently drop an edit a walk just
# found.
if ! jq -e '
  type == "object"
  and all(.. | objects | select(has("commit")) | .commit;
          type == "string" and length == 40 and test("^[0-9a-f]{40}$"))
' "$STATE_FILE" >/dev/null; then
  fail "State file '$STATE_FILE' is missing, is not a JSON object, or holds a malformed commit hash."
fi

# Parallel indexed arrays describe the seven walks. macOS Bash 3.2 has no
# associative arrays, so we keep these as positional lists.
#
# Each index `i` describes one walk:
#
# - `walk_dbs[i]`: the DB slot (world/characters/realmd/logs)
# - `walk_sources[i]`: the source slot under that DB (core/database/playerbots)
# - `walk_owners[i]`: the source repository's GitHub owner
# - `walk_names[i]`: the source repository's GitHub repo name
# - `walk_bases[i]`: the previous build's commit hash in that source repo
# - `walk_heads[i]`: the current build's commit hash in that source repo
# - `walk_patterns[i]`: a `|`-separated list of file-path regexes to match
#
# The backslashes in the patterns are doubled because `awk -v` processes escape
# sequences in the value.
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
  '^sql/base/mangos\\.sql$|^sql/updates/mangos/[^/]+\\.sql$|^sql/base/ahbot/[^/]+\\.sql$|^sql/base/dbc/original_data/[^/]+\\.sql$|^sql/base/dbc/cmangos_fixes/[^/]+\\.sql$|^sql/scriptdev2/[^/]+\\.sql$'
  '^Full_DB/[^/]+\\.sql(\\.gz)?$|^Updates/[^/]+\\.sql$|^Updates/Instances/[^/]+\\.sql$|^ACID/acid_'"$EXPANSION"'\\.sql$|^utilities/cmangos_custom\\.sql$|^locales/[^/]+\\.sql$'
  '^sql/world/[^/]+\\.sql$|^sql/world/'"$EXPANSION"'/[^/]+\\.sql$'
  '^sql/base/characters\\.sql$|^sql/updates/characters/[^/]+\\.sql$'
  '^sql/characters/[^/]+\\.sql$'
  '^sql/base/realmd\\.sql$|^sql/updates/realmd/[^/]+\\.sql$'
  '^sql/base/logs\\.sql$|^sql/updates/logs/[^/]+\\.sql$'
)

# Outputs filled by the walks below: same shape as the input arrays so an entry
# at index `i` corresponds to the `(walk_dbs[i], walk_sources[i])` pair.
found_commits=("" "" "" "" "" "" "")
found_subjects=("" "" "" "" "" "" "")

# Several walks cover the same repository, so clones are reused across them.
clone_root="$(mktemp -d)"
trap 'rm -rf "$clone_root"' EXIT

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

  local clone_dir="$clone_root/${repo//\//__}"
  if [[ ! -d "$clone_dir" ]]; then
    # Blobless so each clone carries commits and trees but no file contents,
    # which is all `git diff-tree` needs to report paths and statuses.
    git clone --filter=blob:none --no-checkout --quiet \
      "https://github.com/$repo.git" "$clone_dir"
  fi

  # Merge commits are excluded because their diff against the first parent
  # would attribute the merged branch's file changes to the merge commit
  # itself, which would give us the wrong commit hash and subject.
  local commit_hashes_newest_first
  commit_hashes_newest_first="$(git -C "$clone_dir" rev-list --no-merges --topo-order \
    "$base..$head")"

  if [[ -z "$commit_hashes_newest_first" ]]; then
    echo "[$db.$source] No commits between $base and $head."
    return 0
  fi

  local total
  total="$(wc -l <<<"$commit_hashes_newest_first")"
  echo "[$db.$source] Walking $total commits newest-first."

  local scanned=0
  local commit_hash
  while IFS= read -r commit_hash; do
    [[ -z "$commit_hash" ]] && continue
    scanned=$((scanned + 1))

    # `core.quotePath` defaults to true, which wraps a path holding a non-ASCII
    # byte in quotes and escapes it, and no watched pattern matches such a
    # value.
    #
    # Rename detection is limited to exact matches because the similarity
    # scoring `-M` performs otherwise reads file contents, which a blobless
    # clone has to fetch one commit at a time. A rename reports both its old
    # and its new path, and the checks below test both, so a watched file
    # renamed away still counts.
    #
    # A parentless commit reports nothing at all without `--root`, so an
    # unrelated history grafted into the window would pass as touching no
    # watched file. The flag changes nothing for every other commit.
    local changed_files
    changed_files="$(git -C "$clone_dir" -c core.quotePath=false diff-tree \
      --no-commit-id --name-status --root -r -M100% "$commit_hash")"

    local has_edit
    has_edit="$(awk -F'\t' -v pattern="$pattern" '
      {
        status = substr($1, 1, 1)

        if (status == "R") {
          previous_path = $2
          path = $3
        } else {
          previous_path = ""
          path = $2
        }

        if (status ~ /^[MRDT]$/ && ((path ~ pattern) ||
          (previous_path != "" && previous_path ~ pattern))) {
          found = 1
        }
      }
      END { if (found) print "1" }' <<<"$changed_files")"

    if [[ "$has_edit" == "1" ]]; then
      local subject
      subject="$(git -C "$clone_dir" log -1 --format=%s "$commit_hash")"
      found_commits[idx]="$commit_hash"
      found_subjects[idx]="$subject"
      echo "[$db.$source] $commit_hash ($subject)"
      break
    fi
  done <<<"$commit_hashes_newest_first"

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
      --arg commit_hash "${found_commits[$i]}" \
      --arg subject "${found_subjects[$i]}" \
      '.[$db][$source] = {commit: $commit_hash, subject: $subject}' \
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
