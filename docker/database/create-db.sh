#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Sets up the databases on the first start, and acknowledges the image's
# migration edits, which a fresh install already has.

set -euo pipefail

# shellcheck source=docker/database/db-functions.sh
source "/opt/scripts/db-functions.sh"

clear_database_ready
clear_change_sentinels
mark_initializing

if [[ "${CMANGOS_PROCESS_CUSTOM_SQL:-0}" = "1" ]]; then
  cmangos_log "[x] Custom SQL processing is enabled."
else
  cmangos_log "[ ] Custom SQL processing is disabled."
fi

full_world_dump="$(get_full_world_dump_file)"

if [[ -z "$full_world_dump" ]]; then
  cmangos_fail "This image has no full world dump. Report it:
https://github.com/mserajnik/cmangos-deploy/issues"
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

ensure_maintenance_db_exists
parse_migration_edits

for i in "${!MIGRATION_EDIT_TARGETS[@]}"; do
  acknowledge_correction "${MIGRATION_EDIT_TARGETS[i]}" "${MIGRATION_EDIT_COMMITS[i]}"
done

mark_initialized

if [[ "${CMANGOS_PROCESS_CUSTOM_SQL:-0}" = "1" ]]; then
  process_custom_sql "/sql/custom"
fi

mark_database_ready
