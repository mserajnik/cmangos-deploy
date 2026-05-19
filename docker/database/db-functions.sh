#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Shared helpers sourced by `create-db.sh` and `update-db.sh`: database CRUD,
# tracked SQL application, migration edit acknowledgement, and halt and confirm
# sentinels.

cmangos_log() {
  echo "[cmangos-deploy]: $*"
}

cmangos_fail() {
  echo "[cmangos-deploy]: ERROR: $*" >&2
  exit 1
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

mark_database_ready() {
  touch /tmp/cmangos-database-ready
}

clear_database_ready() {
  rm -f /tmp/cmangos-database-ready
}

clear_change_sentinels() {
  rm -f /tmp/cmangos-changes-pending /tmp/cmangos-changes-acknowledged
}

database_exists() {
  local db_name="$1"

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" information_schema -N -s -e \
    "SELECT SCHEMA_NAME \
     FROM SCHEMATA \
     WHERE SCHEMA_NAME = '$(sql_escape "$db_name")';" | grep -Fxq "$db_name"
}

create_database() {
  local db_name="$1"
  local silent="${2:-false}"

  if [ "$silent" = false ]; then
    cmangos_log "Creating database '$db_name'..."
  fi

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e \
    "CREATE DATABASE IF NOT EXISTS \`$db_name\` DEFAULT CHARSET utf8 COLLATE utf8_general_ci;"
}

drop_database() {
  local db_name="$1"
  local silent="${2:-false}"

  if [ "$silent" = false ]; then
    cmangos_log "Dropping database '$db_name'..."
  fi

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e \
    "DROP DATABASE IF EXISTS \`$db_name\`;"
}

grant_permissions() {
  local db_name="$1"
  local silent="${2:-false}"

  if [ "$silent" = false ]; then
    cmangos_log "Granting permissions to database user '$MARIADB_USER' for database '$db_name'..."
  fi

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e \
    "CREATE USER IF NOT EXISTS '$MARIADB_USER'@'%' IDENTIFIED BY '$MARIADB_PASSWORD'; \
    GRANT ALL ON \`$db_name\`.* TO '$MARIADB_USER'@'%'; \
    FLUSH PRIVILEGES;"
}

import_sql_file() {
  local db_name="$1"
  local file="$2"

  case "$file" in
  *.gz)
    gzip -dc "$file" | mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name"
    ;;
  *)
    mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" <"$file"
    ;;
  esac
}

import_dump() {
  local db_name="$1"
  local dump_file="$2"

  cmangos_log "Importing initial data for database '$db_name' from '$(basename "$dump_file")'..."
  import_sql_file "$db_name" "$dump_file"
}

# Per-DB tracking table that records which SQL files have already been applied,
# keyed by `<prefix>/<filename>`. Used to skip re-applying unchanged files on
# every start.
tracking_table_name() {
  printf 'cmangos_deploy_applied_sql'
}

ensure_tracking_table() {
  local db_name="$1"
  local table_name

  table_name="$(tracking_table_name)"
  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -e \
    "CREATE TABLE IF NOT EXISTS \`$table_name\` ( \
       \`sql_key\` VARCHAR(255) NOT NULL, \
       \`applied_at\` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, \
       PRIMARY KEY (\`sql_key\`) \
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8;"
}

tracked_sql_applied() {
  local db_name="$1"
  local sql_key="$2"
  local table_name
  local escaped_key

  table_name="$(tracking_table_name)"
  escaped_key="$(sql_escape "$sql_key")"

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -N -s -e \
    "SELECT 1 \
     FROM \`$table_name\` \
     WHERE \`sql_key\` = '$escaped_key' \
     LIMIT 1;" | grep -Fxq "1"
}

mark_tracked_sql_applied() {
  local db_name="$1"
  local sql_key="$2"
  local table_name
  local escaped_key

  table_name="$(tracking_table_name)"
  escaped_key="$(sql_escape "$sql_key")"

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -e \
    "INSERT INTO \`$table_name\` (\`sql_key\`) VALUES ('$escaped_key') \
     ON DUPLICATE KEY UPDATE \`applied_at\` = \`applied_at\`;"
}

apply_tracked_sql_file() {
  local db_name="$1"
  local file="$2"
  local sql_key="$3"
  local description="${4:-$(basename "$file")}"

  if [ ! -f "$file" ]; then
    # The SQL file not existing is not an error, so we return 0 (success) here.
    return 0
  fi

  ensure_tracking_table "$db_name"

  if tracked_sql_applied "$db_name" "$sql_key"; then
    cmangos_log "Skipping already applied SQL '$description' for database '$db_name'."
    return 0
  fi

  cmangos_log "Applying tracked SQL '$description' to database '$db_name'..."
  import_sql_file "$db_name" "$file"
  mark_tracked_sql_applied "$db_name" "$sql_key"
}

apply_tracked_sql_dir() {
  local db_name="$1"
  local dir="$2"
  local key_prefix="$3"
  local recursive="${4:-false}"
  local sql_file

  if [ ! -d "$dir" ]; then
    return 0
  fi

  if [ "$recursive" = true ]; then
    while read -r sql_file; do
      [ -n "$sql_file" ] || continue

      apply_tracked_sql_file \
        "$db_name" \
        "$sql_file" \
        "$key_prefix/$(basename "$sql_file")"
    done <<EOF
$(find "$dir" -type f -name '*.sql' | sort)
EOF
  else
    while read -r sql_file; do
      [ -n "$sql_file" ] || continue

      apply_tracked_sql_file \
        "$db_name" \
        "$sql_file" \
        "$key_prefix/$(basename "$sql_file")"
    done <<EOF
$(find "$dir" -maxdepth 1 -type f -name '*.sql' | sort)
EOF
  fi
}

required_version_table_name() {
  local db_kind="$1"

  case "$db_kind" in
  mangos)
    printf 'db_version'
    ;;
  characters)
    printf 'character_db_version'
    ;;
  realmd)
    printf 'realmd_db_version'
    ;;
  logs)
    printf 'logs_db_version'
    ;;
  *)
    cmangos_fail "Unsupported database kind '$db_kind'."
    ;;
  esac
}

get_current_required_version() {
  local db_name="$1"
  local db_kind="$2"
  local table_name
  local current_version

  table_name="$(required_version_table_name "$db_kind")"

  current_version="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" information_schema -N -s -e \
    "SELECT COLUMN_NAME \
     FROM COLUMNS \
     WHERE TABLE_SCHEMA = '$(sql_escape "$db_name")' \
       AND TABLE_NAME = '$(sql_escape "$table_name")' \
       AND COLUMN_NAME LIKE 'required\\_%\\_${db_kind}\\_%' \
     ORDER BY ORDINAL_POSITION DESC \
     LIMIT 1;")"

  printf '%s' "${current_version#required_}"
}

# Parses the integer revision encoded in a CMaNGOS update file name (or the
# matching `required_*` column name in `db_version`). Strips any leading
# non-digit prefix (`z` for Classic, `s` for TBC, none for WotLK) and
# concatenates the first two underscore-separated digit groups.
#
# This mirrors upstream `InstallFullDB.sh`'s comparison strategy and is
# order-independent, so revisions crossing a digit boundary (e.g. 99999 ->
# 100000) sort correctly.
parse_update_rev() {
  local raw="$1"
  local digits
  local rev

  digits="${raw#"${raw%%[0-9]*}"}"

  if [[ "$digits" =~ ^([0-9]+)_([0-9]+) ]]; then
    rev="$((10#${BASH_REMATCH[1]}${BASH_REMATCH[2]}))"
    printf '%s' "$rev"
  else
    printf '0'
  fi
}

apply_versioned_updates() {
  local db_name="$1"
  local update_dir="$2"
  local db_kind="$3"
  local current_version
  local current_rev
  local applied_count=0
  local update_file
  local update_name
  local update_rev

  if [ ! -d "$update_dir" ]; then
    return 0
  fi

  current_version="$(get_current_required_version "$db_name" "$db_kind")"

  if [ -z "$current_version" ]; then
    cmangos_log "No current required version found for '$db_name'; applying all '$db_kind' updates."
    current_rev=0
  else
    current_rev="$(parse_update_rev "$current_version")"
    cmangos_log "Current required version for '$db_name' is '$current_version' (rev $current_rev)."
  fi

  while read -r update_file; do
    [ -n "$update_file" ] || continue

    update_name="$(basename "$update_file" .sql)"
    update_rev="$(parse_update_rev "$update_name")"

    if [ "$update_rev" -gt "$current_rev" ]; then
      cmangos_log "Applying versioned SQL '$update_name' to database '$db_name'..."
      import_sql_file "$db_name" "$update_file"
      applied_count=$((applied_count + 1))
    fi
  done <<EOF
$(find "$update_dir" -maxdepth 1 -type f -name '*.sql' | sort)
EOF

  if [ "$applied_count" -eq 0 ]; then
    cmangos_log "No new versioned updates found for database '$db_name'."
  fi
}

get_full_world_dump_file() {
  find /sql/database/Full_DB -maxdepth 1 -type f \( -name '*.sql' -o -name '*.sql.gz' \) | sort | tail -n 1
}

set_latest_content_version_marker() {
  local db_name="$1"
  local latest_update=""
  local existing_columns

  latest_update="$(find /sql/database/Updates -maxdepth 1 -type f -name '[0-9]*.sql' | sort | tail -n 1)"

  if [ -z "$latest_update" ]; then
    return 0
  fi

  latest_update="$(basename "$latest_update" .sql)"
  existing_columns="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" information_schema -N -s -e \
    "SELECT COLUMN_NAME \
     FROM COLUMNS \
     WHERE TABLE_SCHEMA = '$(sql_escape "$db_name")' \
       AND TABLE_NAME = 'db_version' \
       AND COLUMN_NAME LIKE 'content\\_%' \
     ORDER BY ORDINAL_POSITION;")"

  if [ -n "$existing_columns" ]; then
    printf '%s\n' "$existing_columns" | while read -r column_name; do
      [ -n "$column_name" ] || continue

      if [ "$column_name" != "content_$latest_update" ]; then
        mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -e \
          "ALTER TABLE db_version DROP COLUMN \`$column_name\`;"
      fi
    done
  fi

  if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" information_schema -N -s -e \
    "SELECT 1 \
     FROM COLUMNS \
     WHERE TABLE_SCHEMA = '$(sql_escape "$db_name")' \
       AND TABLE_NAME = 'db_version' \
       AND COLUMN_NAME = 'content_$latest_update';" | grep -Fxq "1"; then
    mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -e \
      "ALTER TABLE db_version ADD COLUMN \`content_$latest_update\` bit DEFAULT NULL;"
  fi
}

apply_world_content_updates() {
  local world_db="$1"

  apply_tracked_sql_dir "$world_db" "/sql/database/Updates" "database-updates"
  set_latest_content_version_marker "$world_db"
  apply_tracked_sql_dir "$world_db" "/sql/database/Updates/Instances" "database-instance-updates"
}

# Upstream bug workaround: `tbc-db/locales/OtherLocales.sql` drops and re
# re-creates `locales_gameobject` with the pre-`s2485` schema
# (`castbarcaption_loc1..8`), reverting the rename that `mangosd` now expects
# (`opening_text_loc1..8` + `closing_text_loc1..8`). Without this, fresh
# installs of any TBC setup against current `mangos-tbc` + `tbc-db` leave the
# table in the old shape and `mangosd` fails to load locale strings. We
# re-apply the `s2485` rename + add here, gated on the table actually being in
# the old shape so the call is a no-op once upstream fixes the locales file.
# Remove this function and its call sites in `create-db.sh` and
# `world_db_full_install` once the upstream fix lands.
#
# The probe only checks for `castbarcaption_loc1`. If upstream lands a partial
# fix where some of the eight columns are renamed but not all, the probe
# matches and individual `ALTER` statements then fail mid-batch.
# Startup halts loudly via `set -euo pipefail` in the caller, which is the
# desired behavior.
fix_tbc_locales_gameobject() {
  local world_db="$1"
  local has_old_column

  if [ "$CMANGOS_EXPANSION" != "tbc" ]; then
    return 0
  fi

  has_old_column="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" information_schema -N -s -e \
    "SELECT 1 \
     FROM COLUMNS \
     WHERE TABLE_SCHEMA = '$(sql_escape "$world_db")' \
       AND TABLE_NAME = 'locales_gameobject' \
       AND COLUMN_NAME = 'castbarcaption_loc1' \
     LIMIT 1;")"

  if [ -z "$has_old_column" ]; then
    return 0
  fi

  cmangos_log "Re-applying 'locales_gameobject' s2485 schema rename on '$world_db' (upstream tbc-db bug workaround)..."
  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$world_db" <<'SQL'
ALTER TABLE `locales_gameobject` CHANGE `castbarcaption_loc1` `opening_text_loc1` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `castbarcaption_loc2` `opening_text_loc2` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `castbarcaption_loc3` `opening_text_loc3` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `castbarcaption_loc4` `opening_text_loc4` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `castbarcaption_loc5` `opening_text_loc5` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `castbarcaption_loc6` `opening_text_loc6` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `castbarcaption_loc7` `opening_text_loc7` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `castbarcaption_loc8` `opening_text_loc8` varchar(100);
ALTER TABLE `locales_gameobject` ADD COLUMN `closing_text_loc1` varchar(100);
ALTER TABLE `locales_gameobject` ADD COLUMN `closing_text_loc2` varchar(100);
ALTER TABLE `locales_gameobject` ADD COLUMN `closing_text_loc3` varchar(100);
ALTER TABLE `locales_gameobject` ADD COLUMN `closing_text_loc4` varchar(100);
ALTER TABLE `locales_gameobject` ADD COLUMN `closing_text_loc5` varchar(100);
ALTER TABLE `locales_gameobject` ADD COLUMN `closing_text_loc6` varchar(100);
ALTER TABLE `locales_gameobject` ADD COLUMN `closing_text_loc7` varchar(100);
ALTER TABLE `locales_gameobject` ADD COLUMN `closing_text_loc8` varchar(100);
SQL
}

apply_world_static_sql() {
  local world_db="$1"

  apply_tracked_sql_dir "$world_db" "/sql/core/base/ahbot" "core-ahbot"
  apply_tracked_sql_dir "$world_db" "/sql/core/base/dbc/original_data" "core-dbc-original"
  apply_tracked_sql_dir "$world_db" "/sql/core/base/dbc/cmangos_fixes" "core-dbc-fixes"
  apply_tracked_sql_dir "$world_db" "/sql/core/scriptdev2" "core-scriptdev2"
  apply_tracked_sql_file \
    "$world_db" \
    "/sql/database/ACID/acid_${CMANGOS_EXPANSION}.sql" \
    "database-acid/acid_${CMANGOS_EXPANSION}.sql"
  apply_tracked_sql_file \
    "$world_db" \
    "/sql/database/utilities/cmangos_custom.sql" \
    "database-utilities/cmangos_custom.sql"
  apply_tracked_sql_dir "$world_db" "/sql/database/locales" "database-locales"
  apply_tracked_sql_dir "$world_db" "/sql/playerbots/sql/world" "playerbots-world-common"
  apply_tracked_sql_dir \
    "$world_db" \
    "/sql/playerbots/sql/world/${CMANGOS_EXPANSION}" \
    "playerbots-world-${CMANGOS_EXPANSION}"
}

apply_character_static_sql() {
  local characters_db="$1"

  apply_tracked_sql_dir "$characters_db" "/sql/playerbots/sql/characters" "playerbots-characters"
}

configure_realm() {
  local realm_name
  local realm_address

  realm_name="$(sql_escape "$CMANGOS_REALMLIST_NAME")"
  realm_address="$(sql_escape "$CMANGOS_REALMLIST_ADDRESS")"
  cmangos_log "Configuring realm '$CMANGOS_REALMLIST_NAME'..."

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "realmd" -e \
    "INSERT INTO \`realmlist\` \
       (\`id\`, \`name\`, \`address\`, \`port\`, \`icon\`, \`timezone\`, \`allowedSecurityLevel\`) \
     VALUES \
       (1, '$realm_name', '$realm_address', '$CMANGOS_REALMLIST_PORT', '$CMANGOS_REALMLIST_ICON', '$CMANGOS_REALMLIST_TIMEZONE', '$CMANGOS_REALMLIST_ALLOWED_SECURITY_LEVEL') \
     ON DUPLICATE KEY UPDATE \
       \`name\` = VALUES(\`name\`), \
       \`address\` = VALUES(\`address\`), \
       \`port\` = VALUES(\`port\`), \
       \`icon\` = VALUES(\`icon\`), \
       \`timezone\` = VALUES(\`timezone\`), \
       \`allowedSecurityLevel\` = VALUES(\`allowedSecurityLevel\`);"
}

ensure_maintenance_db_exists() {
  create_database "maintenance" true
  grant_permissions "maintenance" true

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -e \
    "CREATE TABLE IF NOT EXISTS \`migration_corrections\` ( \
      \`db_name\` VARCHAR(64) NOT NULL, \
      \`commit_hash\` CHAR(40) NOT NULL, \
      \`acknowledged_at\` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, \
      PRIMARY KEY (\`db_name\`, \`commit_hash\`) \
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8;"

  # One-time rename of the legacy `commit_sha` column to `commit_hash` for
  # installs that were created before the renaming. TODO: removable once we can
  # assume all existing installs have run with the new column name.
  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -e \
    "ALTER TABLE \`migration_corrections\` \
     CHANGE COLUMN IF EXISTS \`commit_sha\` \`commit_hash\` CHAR(40) NOT NULL;"
}

correction_acknowledged() {
  local db_name="$1"
  local commit_hash="$2"
  local count

  count="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -N -s -e \
    "SELECT COUNT(*) FROM \`migration_corrections\` \
    WHERE \`db_name\` = '$(sql_escape "$db_name")' \
    AND \`commit_hash\` = '$(sql_escape "$commit_hash")';")"

  [ "$count" -gt 0 ]
}

acknowledge_correction() {
  local db_name="$1"
  local commit_hash="$2"

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -e \
    "INSERT IGNORE INTO \`migration_corrections\` (\`db_name\`, \`commit_hash\`) \
    VALUES ('$(sql_escape "$db_name")', '$(sql_escape "$commit_hash")');"
}

# The `CMANGOS_MIGRATION_EDITS` build argument is baked into
# `/sql/migration-edits` at image build time; manual builds leave the file
# empty and all per-DB source arrays stay empty, which makes every per-database
# correction a no-op.
#
# Leaks the per-DB `MIGRATION_EDIT_*` globals to the parent script by design;
# `update-db.sh` and `create-db.sh` consume them after sourcing.
# The arrays are parallel: index `i` of `*_SOURCES` and `*_COMMIT_HASHES`
# describes one `(source, commit hash)` pair that needs acknowledgement for
# that DB.
# shellcheck disable=SC2034
parse_migration_edits() {
  MIGRATION_EDIT_WORLD_SOURCES=()
  MIGRATION_EDIT_WORLD_COMMIT_HASHES=()
  MIGRATION_EDIT_CHARACTERS_SOURCES=()
  MIGRATION_EDIT_CHARACTERS_COMMIT_HASHES=()
  MIGRATION_EDIT_REALMD_SOURCES=()
  MIGRATION_EDIT_REALMD_COMMIT_HASHES=()
  MIGRATION_EDIT_LOGS_SOURCES=()
  MIGRATION_EDIT_LOGS_COMMIT_HASHES=()

  local file="/sql/migration-edits"
  if [ ! -f "$file" ]; then
    return 0
  fi

  local raw
  raw="$(head -n1 "$file" | tr -d '\r\n')"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"

  if [ -z "$raw" ]; then
    return 0
  fi

  local slot db entries item src commit_hash
  local saved_ifs="$IFS"
  IFS='|'
  for slot in $raw; do
    IFS="$saved_ifs"
    db="${slot%%:*}"
    entries="${slot#*:}"
    if [ -z "$entries" ]; then
      IFS='|'
      continue
    fi

    IFS=','
    for item in $entries; do
      src="${item%%@*}"
      commit_hash="${item#*@}"
      [ -z "$src" ] && continue
      [ -z "$commit_hash" ] && continue

      case "$db" in
      world)
        MIGRATION_EDIT_WORLD_SOURCES+=("$src")
        MIGRATION_EDIT_WORLD_COMMIT_HASHES+=("$commit_hash")
        ;;
      characters)
        MIGRATION_EDIT_CHARACTERS_SOURCES+=("$src")
        MIGRATION_EDIT_CHARACTERS_COMMIT_HASHES+=("$commit_hash")
        ;;
      realmd)
        MIGRATION_EDIT_REALMD_SOURCES+=("$src")
        MIGRATION_EDIT_REALMD_COMMIT_HASHES+=("$commit_hash")
        ;;
      logs)
        MIGRATION_EDIT_LOGS_SOURCES+=("$src")
        MIGRATION_EDIT_LOGS_COMMIT_HASHES+=("$commit_hash")
        ;;
      esac
    done
    IFS='|'
  done
  IFS="$saved_ifs"
}

# Pre-acknowledges every baked migration edit. Used on fresh install so a clean
# DB never triggers a world database re-creation or halt on its first start.
pre_acknowledge_all_baked() {
  local i
  for i in "${!MIGRATION_EDIT_WORLD_SOURCES[@]}"; do
    acknowledge_correction "mangos" "${MIGRATION_EDIT_WORLD_COMMIT_HASHES[i]}"
  done
  for i in "${!MIGRATION_EDIT_CHARACTERS_SOURCES[@]}"; do
    acknowledge_correction "characters" "${MIGRATION_EDIT_CHARACTERS_COMMIT_HASHES[i]}"
  done
  for i in "${!MIGRATION_EDIT_REALMD_SOURCES[@]}"; do
    acknowledge_correction "realmd" "${MIGRATION_EDIT_REALMD_COMMIT_HASHES[i]}"
  done
  for i in "${!MIGRATION_EDIT_LOGS_SOURCES[@]}"; do
    acknowledge_correction "logs" "${MIGRATION_EDIT_LOGS_COMMIT_HASHES[i]}"
  done
}

# Builds the world database from scratch using the same SQL inputs
# `create-db.sh` uses for a fresh install. Used to re-create the world database
# when a migration edit is detected and
# `CMANGOS_ENABLE_AUTOMATIC_WORLD_DB_CORRECTIONS=1`. GM-applied edits to the
# world database are NOT preserved; the user is expected to restore from their
# own backup if they need them back.
world_db_full_install() {
  local full_world_dump
  full_world_dump="$(get_full_world_dump_file)"

  if [ -z "$full_world_dump" ]; then
    cmangos_fail "Unable to locate a full world dump in '/sql/database/Full_DB'."
  fi

  drop_database "mangos"
  create_database "mangos"
  grant_permissions "mangos"

  import_dump "mangos" "/sql/core/base/mangos.sql"
  import_dump "mangos" "$full_world_dump"

  apply_world_content_updates "mangos"
  apply_versioned_updates "mangos" "/sql/core/updates/mangos" "mangos"
  apply_world_static_sql "mangos"
  fix_tbc_locales_gameobject "mangos"
}

PENDING_DB_NAMES=()
PENDING_DB_SOURCES=()
PENDING_DB_COMMIT_HASHES=()

process_world_correction() {
  if [ "${#MIGRATION_EDIT_WORLD_SOURCES[@]}" -eq 0 ]; then
    return 0
  fi

  local i
  local src
  local commit_hash
  local unack_sources=()
  local unack_commit_hashes=()

  for i in "${!MIGRATION_EDIT_WORLD_SOURCES[@]}"; do
    src="${MIGRATION_EDIT_WORLD_SOURCES[i]}"
    commit_hash="${MIGRATION_EDIT_WORLD_COMMIT_HASHES[i]}"
    if ! correction_acknowledged "mangos" "$commit_hash"; then
      unack_sources+=("$src")
      unack_commit_hashes+=("$commit_hash")
    fi
  done

  if [ "${#unack_commit_hashes[@]}" -eq 0 ]; then
    return 0
  fi

  local enable_auto="${CMANGOS_ENABLE_AUTOMATIC_WORLD_DB_CORRECTIONS:-0}"
  local halt_on_edits="${CMANGOS_HALT_ON_MIGRATION_EDITS:-0}"

  if [ "$enable_auto" = "1" ]; then
    cmangos_log "Re-creating world database to apply migration edits..."
    world_db_full_install
    for i in "${!unack_commit_hashes[@]}"; do
      acknowledge_correction "mangos" "${unack_commit_hashes[i]}"
    done
    return 0
  fi

  if [ "$halt_on_edits" = "1" ]; then
    for i in "${!unack_sources[@]}"; do
      PENDING_DB_NAMES+=("mangos")
      PENDING_DB_SOURCES+=("${unack_sources[i]}")
      PENDING_DB_COMMIT_HASHES+=("${unack_commit_hashes[i]}")
    done
    return 0
  fi

  # We deliberately do not record an acknowledgement here so the warning
  # repeats on every start until the user takes action.
  for i in "${!unack_sources[@]}"; do
    cmangos_log "WARNING: Migration edit detected for world database (${unack_sources[i]}@${unack_commit_hashes[i]:0:7}) but both 'CMANGOS_ENABLE_AUTOMATIC_WORLD_DB_CORRECTIONS' and 'CMANGOS_HALT_ON_MIGRATION_EDITS' are disabled; continuing without applying or acknowledging." >&2
  done
}

process_userstate_correction() {
  local db_name="$1"
  local sources_ref
  local commit_hashes_ref

  case "$db_name" in
  characters)
    sources_ref="MIGRATION_EDIT_CHARACTERS_SOURCES[@]"
    commit_hashes_ref="MIGRATION_EDIT_CHARACTERS_COMMIT_HASHES[@]"
    ;;
  realmd)
    sources_ref="MIGRATION_EDIT_REALMD_SOURCES[@]"
    commit_hashes_ref="MIGRATION_EDIT_REALMD_COMMIT_HASHES[@]"
    ;;
  logs)
    sources_ref="MIGRATION_EDIT_LOGS_SOURCES[@]"
    commit_hashes_ref="MIGRATION_EDIT_LOGS_COMMIT_HASHES[@]"
    ;;
  *)
    cmangos_fail "Unsupported user-state database '$db_name'."
    ;;
  esac

  local sources=("${!sources_ref}")
  local commit_hashes=("${!commit_hashes_ref}")

  if [ "${#sources[@]}" -eq 0 ]; then
    return 0
  fi

  local halt_on_edits="${CMANGOS_HALT_ON_MIGRATION_EDITS:-0}"

  local i
  local src
  local commit_hash
  for i in "${!sources[@]}"; do
    src="${sources[i]}"
    commit_hash="${commit_hashes[i]}"
    if correction_acknowledged "$db_name" "$commit_hash"; then
      continue
    fi

    if [ "$halt_on_edits" = "1" ]; then
      PENDING_DB_NAMES+=("$db_name")
      PENDING_DB_SOURCES+=("$src")
      PENDING_DB_COMMIT_HASHES+=("$commit_hash")
      continue
    fi

    # We deliberately do not record an acknowledgement here so the warning
    # repeats on every start until the user takes action.
    cmangos_log "WARNING: Migration edit detected for '$db_name' database ($src@${commit_hash:0:7}) but 'CMANGOS_HALT_ON_MIGRATION_EDITS' is disabled; continuing without acknowledging." >&2
  done
}

# Maps a `(source, commit hash)` pair to the upstream commit URL the user
# should read while reconciling the change.
correction_source_url() {
  local src="$1"
  local commit_hash="$2"

  case "$src" in
  core)
    printf 'https://github.com/cmangos/mangos-%s/commit/%s' \
      "$CMANGOS_EXPANSION" "$commit_hash"
    ;;
  database)
    printf 'https://github.com/cmangos/%s-db/commit/%s' \
      "$CMANGOS_EXPANSION" "$commit_hash"
    ;;
  playerbots)
    printf 'https://github.com/cmangos/playerbots/commit/%s' "$commit_hash"
    ;;
  *) ;;
  esac
}

print_correction_abort_message() {
  cat >&2 <<'EOF'
[cmangos-deploy]: ERROR: Migration edits detected in CMaNGOS that affect the
following databases. cmangos-deploy will not apply these changes for you
because they could overwrite data you (or your players) generated. Startup is
halted; no databases have been modified.

Affected databases:
EOF

  local i=0
  local name
  local src
  local commit_hash
  local url
  while [ "$i" -lt "${#PENDING_DB_NAMES[@]}" ]; do
    name="${PENDING_DB_NAMES[$i]}"
    src="${PENDING_DB_SOURCES[$i]}"
    commit_hash="${PENDING_DB_COMMIT_HASHES[$i]}"
    url="$(correction_source_url "$src" "$commit_hash")"
    printf '  - %s (%s)\n' "$name" "$src" >&2
    if [ -n "$url" ]; then
      printf '    %s\n' "$url" >&2
    fi
    i=$((i + 1))
  done

  cat >&2 <<'EOF'

For each affected database:

  1. Open the GitHub link above to see what changed.
  2. Apply the equivalent SQL to the running database yourself:
       docker compose exec database mariadb -u root -p <database>
     (mariadb will prompt for the password; it matches your
     `MARIADB_ROOT_PASSWORD` setting in `compose.yaml`.)
  3. When you have applied the changes, confirm by running on the host:
       docker compose exec database cmangos-confirm-changes

To abort instead, run on the host:
  docker compose down

While the container is paused, MariaDB is reachable inside the container via
the internal socket. TCP access on port 3306 is not available during the pause.
CMaNGOS stays offline. Nothing restarts on its own; take as long as you need.

Note: When you confirm, cmangos-deploy treats the listed commits as applied and
continues. It does not check your database to verify that the changes you made
match what the commits describe. If your manual fix is incorrect or incomplete,
the database will be in an inconsistent state and CMaNGOS may fail to start.
The responsibility for matching what the commits do is yours; cmangos-deploy
provides no further support for resolving these issues.
EOF
}

wait_for_change_ack() {
  touch /tmp/cmangos-changes-pending

  while [ ! -f /tmp/cmangos-changes-acknowledged ]; do
    sleep 5
  done

  rm -f /tmp/cmangos-changes-pending /tmp/cmangos-changes-acknowledged
}

process_custom_sql() {
  local file_directory="$1"
  local file_count

  if [ ! -d "$file_directory" ]; then
    cmangos_log "WARNING: Custom SQL file directory '$file_directory' does not exist." >&2
    return 0
  fi

  file_count=$(find "$file_directory" -name "*.sql" -type f | wc -l)
  cmangos_log "Found $file_count custom SQL file(s) to process."

  if [ "$file_count" -gt 0 ]; then
    find "$file_directory" -name "*.sql" -type f | sort | while read -r sql_file; do
      cmangos_log "Processing custom SQL file '$(basename "$sql_file")'..."

      if ! import_sql_file "mangos" "$sql_file"; then
        cmangos_log "ERROR: Failed to process custom SQL file '$(basename "$sql_file")'." >&2
      fi
    done
  fi
}
