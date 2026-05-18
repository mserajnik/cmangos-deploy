#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs on every subsequent container start (via `/always-initdb.d`) to apply
# pending migrations and act on baked migration edit metadata, either
# re-creating the world database or halting startup until the user runs
# `cmangos-confirm-changes`.

set -euo pipefail

# shellcheck source=docker/database/db-functions.sh
source "/opt/scripts/db-functions.sh"

clear_database_ready
clear_change_sentinels

if [ "${CMANGOS_ENABLE_AUTOMATIC_WORLD_DB_CORRECTIONS:-0}" = "1" ]; then
  cmangos_log "[x] Automatic world database corrections are enabled."
else
  cmangos_log "[ ] Automatic world database corrections are disabled."
fi

if [ "${CMANGOS_HALT_ON_MIGRATION_EDITS:-0}" = "1" ]; then
  cmangos_log "[x] Halting on migration edits is enabled."
else
  cmangos_log "[ ] Halting on migration edits is disabled."
fi

if [ "${CMANGOS_PROCESS_CUSTOM_SQL:-0}" = "1" ]; then
  cmangos_log "[x] Custom SQL processing is enabled."
else
  cmangos_log "[ ] Custom SQL processing is disabled."
fi

if ! database_exists "mangos" || ! database_exists "characters" || ! database_exists "realmd" || ! database_exists "logs"; then
  cmangos_fail "Expected databases do not exist, refusing to run update hooks."
fi

ensure_maintenance_db_exists
parse_migration_edits

process_world_correction
process_userstate_correction "characters"
process_userstate_correction "realmd"
process_userstate_correction "logs"

if [ "${#PENDING_DB_NAMES[@]}" -gt 0 ]; then
  print_correction_abort_message
  wait_for_change_ack

  i=0
  while [ "$i" -lt "${#PENDING_DB_NAMES[@]}" ]; do
    acknowledge_correction "${PENDING_DB_NAMES[$i]}" "${PENDING_DB_SHAS[$i]}"
    i=$((i + 1))
  done

  cmangos_log "Migration edits acknowledged; continuing startup."
fi

apply_world_content_updates "mangos"
apply_versioned_updates "mangos" "/sql/core/updates/mangos" "mangos"
apply_versioned_updates "characters" "/sql/core/updates/characters" "characters"
apply_versioned_updates "realmd" "/sql/core/updates/realmd" "realmd"
apply_versioned_updates "logs" "/sql/core/updates/logs" "logs"
apply_world_static_sql "mangos"
apply_character_static_sql "characters"

if [ "${CMANGOS_PROCESS_CUSTOM_SQL:-0}" = "1" ]; then
  process_custom_sql "/sql/custom"
fi

configure_realm

mark_database_ready
