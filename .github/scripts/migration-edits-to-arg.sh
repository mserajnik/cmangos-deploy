#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Flattens a per-expansion migration edit state file to the
# `CMANGOS_MIGRATION_EDITS` build argument format:
# `<db>:<src1>@<sha1>,<src2>@<sha2>|...` (null source entries are omitted; a DB
# whose sources are all null renders as `<db>:`).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

if [[ "$#" -ne 1 ]]; then
  fail "Usage: $0 <state-file>"
fi

state_file="$1"

if [[ ! -f "$state_file" ]]; then
  fail "State file '$state_file' does not exist."
fi

# We enumerate slots in a stable order so the rendered string is deterministic
# and matches what runtime parsers expect.
db_names=(world characters realmd logs)
parts=()

for db in "${db_names[@]}"; do
  entries="$(jq -r --arg db "$db" '
    .[$db] // {}
    | to_entries
    | map(select(.value != null))
    | map("\(.key)@\(.value.commit)")
    | join(",")
  ' "$state_file")"
  parts+=("$db:$entries")
done

# Join with `|` without trailing separator.
output=""
for part in "${parts[@]}"; do
  if [ -z "$output" ]; then
    output="$part"
  else
    output+="|$part"
  fi
done

printf '%s\n' "$output"
