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

# Runs once on first container start (via `/docker-entrypoint-initdb.d`) to
# create and seed the four CMaNGOS databases, then pre-acknowledges any baked
# migration edits so the next startup does not re-run a re-creation or halt for
# them.

set -euo pipefail

# shellcheck source=docker/database/db-functions.sh
source "/opt/scripts/db-functions.sh"

clear_database_ready
clear_change_sentinels

if [ "${CMANGOS_PROCESS_CUSTOM_SQL:-0}" = "1" ]; then
  cmangos_log "[x] Custom SQL processing is enabled."
else
  cmangos_log "[ ] Custom SQL processing is disabled."
fi

full_world_dump="$(get_full_world_dump_file)"

if [ -z "$full_world_dump" ]; then
  cmangos_fail "Unable to locate a full world dump in '/sql/database/Full_DB'."
fi

create_database "mangos"
create_database "characters"
create_database "realmd"
create_database "logs"

grant_permissions "mangos"
grant_permissions "characters"
grant_permissions "realmd"
grant_permissions "logs"

import_dump "mangos" "/sql/core/base/mangos.sql"
import_dump "characters" "/sql/core/base/characters.sql"
import_dump "realmd" "/sql/core/base/realmd.sql"
import_dump "logs" "/sql/core/base/logs.sql"
import_dump "mangos" "$full_world_dump"

apply_world_content_updates "mangos"
apply_versioned_updates "mangos" "/sql/core/updates/mangos" "mangos"
apply_versioned_updates "characters" "/sql/core/updates/characters" "characters"
apply_versioned_updates "realmd" "/sql/core/updates/realmd" "realmd"
apply_versioned_updates "logs" "/sql/core/updates/logs" "logs"
apply_world_static_sql "mangos"
fix_tbc_locales_gameobject "mangos"
apply_character_static_sql "characters"

configure_realm

if [ "${CMANGOS_PROCESS_CUSTOM_SQL:-0}" = "1" ]; then
  process_custom_sql "/sql/custom"
fi

# A fresh install is already at the latest state, so any migration edits
# flagged in the baked state file are pre-acknowledged to avoid triggering an
# unnecessary world database re-creation or halt on the next start.
ensure_maintenance_db_exists
parse_migration_edits
pre_acknowledge_all_baked

mark_database_ready
