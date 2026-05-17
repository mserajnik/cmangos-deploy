#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Resolves the default core and database repository URLs for a given expansion,
# falling back to the upstream CMaNGOS repositories when the custom workflow's
# user inputs are empty.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env EXPANSION

# shellcheck disable=SC2153
expansion="$(trim "$EXPANSION")"
core_repository_url_input="$(trim "${CORE_REPOSITORY_URL_INPUT:-}")"
database_repository_url_input="$(trim "${DATABASE_REPOSITORY_URL_INPUT:-}")"

case "$expansion" in
classic)
  default_core_repository_url="https://github.com/cmangos/mangos-classic.git"
  default_database_repository_url="https://github.com/cmangos/classic-db.git"
  ;;
tbc)
  default_core_repository_url="https://github.com/cmangos/mangos-tbc.git"
  default_database_repository_url="https://github.com/cmangos/tbc-db.git"
  ;;
wotlk)
  default_core_repository_url="https://github.com/cmangos/mangos-wotlk.git"
  default_database_repository_url="https://github.com/cmangos/wotlk-db.git"
  ;;
*)
  fail "Unsupported expansion '$expansion'."
  ;;
esac

if [[ -n "$core_repository_url_input" ]]; then
  core_repository_url="$core_repository_url_input"
else
  core_repository_url="$default_core_repository_url"
fi

if [[ -n "$database_repository_url_input" ]]; then
  database_repository_url="$database_repository_url_input"
else
  database_repository_url="$default_database_repository_url"
fi

write_output core_repository_url "$core_repository_url"
write_output database_repository_url "$database_repository_url"
