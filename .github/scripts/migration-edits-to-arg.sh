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
