#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Flattens a per-expansion migration edit state file to the
# `CMANGOS_MIGRATION_EDITS` build argument: pipe-separated database entries,
# each `<database>:<source>@<commit-hash>,...` (null source entries are
# omitted; a database whose sources are all null renders as `<database>:`).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

if [[ "$#" -ne 1 ]]; then
  fail "Usage: $0 <state-file>"
fi

state_file="$1"

# A state file `jq` cannot read as an object would yield an empty token, which
# reads as "no recorded edits".
if ! jq -e '
  type == "object"
  and all(.. | objects | select(has("commit")) | .commit;
          type == "string" and length == 40 and test("^[0-9a-f]{40}$"))
' "$state_file" >/dev/null; then
  fail "State file '$state_file' is missing, is not a JSON object, or holds a malformed commit hash."
fi

jq -r '
  ["world", "characters", "realmd", "logs"] as $order
  | [$order[] as $db |
      "\($db):" +
      (.[$db] // {}
        | to_entries
        | map(select(.value != null and .value.commit != null))
        | map("\(.key)@\(.value.commit)")
        | join(","))
    ]
  | join("|")
' "$state_file"
