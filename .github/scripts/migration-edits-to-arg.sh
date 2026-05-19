#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Flattens a per-expansion migration edit state file to the
# `CMANGOS_MIGRATION_EDITS` build argument: pipe-separated database entries,
# each `<database>:<source>@<commit hash>,...` (null source entries are
# omitted; a database whose sources are all null renders as `<database>:`).

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

jq -r '
  ["world", "characters", "realmd", "logs"] as $order
  | [$order[] as $db |
      "\($db):" +
      (.[$db] // {}
        | to_entries
        | map(select(.value != null))
        | map("\(.key)@\(.value.commit)")
        | join(","))
    ]
  | join("|")
' "$state_file"
