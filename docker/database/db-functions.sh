# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# shellcheck shell=bash

# Helpers for `create-db.sh` and `update-db.sh`.

cmangos_log() {
  echo "[cmangos-deploy]: $*"
}

cmangos_fail() {
  echo "[cmangos-deploy]: ERROR: $*" >&2
  exit 1
}

sql_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
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

# A data directory with the first marker is from a setup that did not finish.
INITIALIZING_MARKER="/var/lib/mysql/.cmangos-deploy-initializing"
INITIALIZED_MARKER="/var/lib/mysql/.cmangos-deploy-initialized"

mark_initializing() {
  touch "$INITIALIZING_MARKER"
}

mark_initialized() {
  mv "$INITIALIZING_MARKER" "$INITIALIZED_MARKER"
}

# A data directory from before the markers counts as set up when its world
# database contains data.
require_initialized() {
  if [[ -f "$INITIALIZED_MARKER" ]]; then
    return 0
  fi

  if [[ ! -f "$INITIALIZING_MARKER" ]] &&
    mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -N -s -e \
      "SELECT 1 FROM \`mangos\`.\`creature_template\` LIMIT 1;" |
    grep -q 1; then
    touch "$INITIALIZED_MARKER"
    return 0
  fi

  cmangos_fail "The databases are not set up completely. If this is a new installation, remove the database volume and run 'docker compose up -d' again. Otherwise, the volume contains your characters: remove it only if you have a backup, and restore the backup once the databases are set up again:
https://github.com/mserajnik/cmangos-deploy/blob/master/docs/usage.md#restoring-a-backup"
}

create_database() {
  local db_name="$1"
  local silent="${2:-false}"

  if [[ "$silent" = false ]]; then
    cmangos_log "Creating the '$db_name' database..."
  fi

  if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e \
    "CREATE DATABASE IF NOT EXISTS \`$db_name\` DEFAULT CHARSET utf8 COLLATE utf8_general_ci;"; then
    cmangos_fail "Failed to create the '$db_name' database. See the error above."
  fi
}

drop_database() {
  local db_name="$1"
  local silent="${2:-false}"

  if [[ "$silent" = false ]]; then
    cmangos_log "Dropping the '$db_name' database..."
  fi

  if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e \
    "DROP DATABASE IF EXISTS \`$db_name\`;"; then
    cmangos_fail "Failed to drop the '$db_name' database. See the error above."
  fi
}

grant_permissions() {
  local db_name="$1"
  local silent="${2:-false}"
  local user
  local password

  if [[ "$silent" = false ]]; then
    cmangos_log "Granting the '$MARIADB_USER' user access to the '$db_name' database..."
  fi

  user="$(sql_escape "$MARIADB_USER")"
  password="$(sql_escape "$MARIADB_PASSWORD")"

  if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e \
    "CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$password'; \
    GRANT ALL ON \`$db_name\`.* TO '$user'@'%'; \
    FLUSH PRIVILEGES;"; then
    cmangos_fail "Failed to grant the '$MARIADB_USER' user access to the '$db_name' database. See the error above."
  fi
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

  cmangos_log "Importing the initial data for the '$db_name' database from '$(basename "$dump_file")'..."

  if ! import_sql_file "$db_name" "$dump_file"; then
    cmangos_fail "Failed to import the initial data for the '$db_name' database from '$(basename "$dump_file")'. See the error above."
  fi
}

# The name of the table in each database that records the applied SQL files,
# keyed by `<prefix>/<filename>`.
tracking_table_name() {
  printf 'cmangos_deploy_applied_sql'
}

ensure_tracking_table() {
  local db_name="$1"
  local table_name

  table_name="$(tracking_table_name)"
  if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -e \
    "CREATE TABLE IF NOT EXISTS \`$table_name\` ( \
       \`sql_key\` VARCHAR(255) NOT NULL, \
       \`applied_at\` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, \
       PRIMARY KEY (\`sql_key\`) \
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8;"; then
    cmangos_fail "Failed to set up the record of applied SQL files in the '$db_name' database. See the error above."
  fi
}

tracked_sql_applied() {
  local db_name="$1"
  local sql_key="$2"
  local table_name
  local escaped_key
  local result
  local status

  table_name="$(tracking_table_name)"
  escaped_key="$(sql_escape "$sql_key")"

  set +e
  result="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -N -s -e \
    "SELECT 1 \
     FROM \`$table_name\` \
     WHERE \`sql_key\` = '$escaped_key' \
     LIMIT 1;")"
  status=$?
  set -e

  # Callers use this as a condition, where `set -e` does not apply, so check
  # the query status by hand.
  if [[ $status -ne 0 ]]; then
    cmangos_fail "Failed to read the record of applied SQL files in the '$db_name' database. See the error above."
  fi

  grep -Fxq "1" <<<"$result"
}

apply_tracked_sql_file() {
  local db_name="$1"
  local file="$2"
  local sql_key="$3"
  local description="${4:-$(basename "$file")}"
  local table_name
  local escaped_key

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  ensure_tracking_table "$db_name"

  if tracked_sql_applied "$db_name" "$sql_key"; then
    cmangos_log "Skipping the tracked SQL file '$description', which has already been applied to the '$db_name' database."
    return 0
  fi

  cmangos_log "Applying the tracked SQL file '$description' to the '$db_name' database..."
  table_name="$(tracking_table_name)"
  escaped_key="$(sql_escape "$sql_key")"
  # The file and its record share one session, so the script cannot exit
  # between them when Docker stops the container. The `mariadb` client stops at
  # the first failed statement, which leaves the file unrecorded. `set -e` does
  # not apply in the condition, so a failed `cat` ends the group itself, before
  # the record.
  if ! {
    cat "$file" || exit
    echo
    echo "INSERT INTO \`$db_name\`.\`$table_name\` (\`sql_key\`) VALUES ('$escaped_key')" \
      "ON DUPLICATE KEY UPDATE \`applied_at\` = \`applied_at\`;"
  } | mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name"; then
    cmangos_fail "Failed to apply the tracked SQL file '$description' to the '$db_name' database. See the error above."
  fi
}

apply_tracked_sql_dir() {
  local db_name="$1"
  local dir="$2"
  local key_prefix="$3"
  local sql_file
  local status

  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  # Check `find` on its own, so a failure cannot read as an empty directory.
  # The names are passed through a file, because a command substitution drops
  # NUL bytes.
  local listing
  local sql_file_list=()
  listing="$(mktemp)"
  set +e
  find "$dir" -maxdepth 1 -type f -name '*.sql' -print0 >"$listing"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    rm -f "$listing"
    cmangos_fail "Failed to list the tracked SQL files in '$dir'. See the error above."
  fi

  set +e
  sort -z -o "$listing" "$listing"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    rm -f "$listing"
    cmangos_fail "Failed to sort the tracked SQL file listing in '$dir'. See the error above."
  fi

  mapfile -d '' -t sql_file_list <"$listing"
  rm -f "$listing"

  for sql_file in "${sql_file_list[@]}"; do
    apply_tracked_sql_file \
      "$db_name" \
      "$sql_file" \
      "$key_prefix/$(basename "$sql_file")"
  done
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
      cmangos_fail "This image cannot read the required version of the '$db_kind' database. Report it:
https://github.com/mserajnik/cmangos-deploy/issues"
      ;;
  esac
}

get_current_required_version() {
  local db_name="$1"
  local db_kind="$2"
  local table_name
  local current_version
  local status

  # `cmangos_fail` in a command substitution exits only the subshell.
  table_name="$(required_version_table_name "$db_kind")" || return 1

  set +e
  current_version="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" information_schema -N -s -e \
    "SELECT COLUMN_NAME \
     FROM COLUMNS \
     WHERE TABLE_SCHEMA = '$(sql_escape "$db_name")' \
       AND TABLE_NAME = '$(sql_escape "$table_name")' \
       AND COLUMN_NAME LIKE 'required\\_%\\_${db_kind}\\_%' \
     ORDER BY ORDINAL_POSITION DESC \
     LIMIT 1;")"
  status=$?
  set -e

  # Callers run this in a command substitution, where `set -e` does not apply,
  # so check the query status by hand. A failed query would otherwise apply
  # every update again.
  if [[ $status -ne 0 ]]; then
    cmangos_fail "Failed to read the required version of the '$db_name' database. See the error above."
  fi

  printf '%s' "${current_version#required_}"
}

# The revision in a CMaNGOS update file name or `required_*` column: the first
# two digit groups joined, after any letter prefix (`z` for Classic, `s` for
# TBC), as upstream's `InstallFullDB.sh` compares them.
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
  local update_files
  local update_name
  local update_rev
  local status

  if [[ ! -d "$update_dir" ]]; then
    return 0
  fi

  # Check `find` on its own, as in `apply_tracked_sql_dir`.
  set +e
  update_files="$(find "$update_dir" -maxdepth 1 -type f -name '*.sql')"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    cmangos_fail "Failed to list the versioned updates in '$update_dir'. See the error above."
  fi

  update_files="$(sort <<<"$update_files")"

  current_version="$(get_current_required_version "$db_name" "$db_kind")"

  if [[ -z "$current_version" ]]; then
    cmangos_log "The '$db_name' database has no required version yet. Applying all of its versioned updates..."
    current_rev=0
  else
    current_rev="$(parse_update_rev "$current_version")"
    cmangos_log "The required version of the '$db_name' database is '$current_version'."
  fi

  while read -r update_file; do
    [[ -n "$update_file" ]] || continue

    update_name="$(basename "$update_file" .sql)"
    update_rev="$(parse_update_rev "$update_name")"

    if [[ "$update_rev" -gt "$current_rev" ]]; then
      cmangos_log "Applying the versioned update '$update_name' to the '$db_name' database..."
      if ! import_sql_file "$db_name" "$update_file"; then
        cmangos_fail "Failed to apply the versioned update '$update_name' to the '$db_name' database. See the error above."
      fi
      applied_count=$((applied_count + 1))
    fi
  done <<<"$update_files"

  if [[ "$applied_count" -eq 0 ]]; then
    cmangos_log "Found no new versioned updates for the '$db_name' database."
  fi
}

get_full_world_dump_file() {
  local dumps
  local status

  set +e
  dumps="$(find /sql/database/Full_DB -maxdepth 1 -type f \
    \( -name '*.sql' -o -name '*.sql.gz' \))"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    cmangos_fail "Failed to list the full world dumps from 'cmangos/$CMANGOS_EXPANSION-db' in '/sql/database/Full_DB'. See the error above."
  fi

  sort <<<"$dumps" | tail -n 1
}

set_latest_content_version_marker() {
  local db_name="$1"
  local latest_update=""
  local existing_columns
  local marker_column
  local updates
  local status

  set +e
  updates="$(find /sql/database/Updates -maxdepth 1 -type f -name '[0-9]*.sql')"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    cmangos_fail "Failed to list the content updates from 'cmangos/$CMANGOS_EXPANSION-db' in '/sql/database/Updates'. See the error above."
  fi

  latest_update="$(sort <<<"$updates" | tail -n 1)"

  if [[ -z "$latest_update" ]]; then
    return 0
  fi

  latest_update="$(basename "$latest_update" .sql)"

  set +e
  existing_columns="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" information_schema -N -s -e \
    "SELECT COLUMN_NAME \
     FROM COLUMNS \
     WHERE TABLE_SCHEMA = '$(sql_escape "$db_name")' \
       AND TABLE_NAME = 'db_version' \
       AND COLUMN_NAME LIKE 'content\\_%' \
     ORDER BY ORDINAL_POSITION;")"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    cmangos_fail "Failed to read the content version of the world database. See the error above."
  fi

  if [[ -n "$existing_columns" ]]; then
    printf '%s\n' "$existing_columns" | while read -r column_name; do
      [[ -n "$column_name" ]] || continue

      if [[ "$column_name" != "content_$latest_update" ]]; then
        if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -e \
          "ALTER TABLE db_version DROP COLUMN \`$column_name\`;"; then
          cmangos_fail "Failed to update the content version of the world database. See the error above."
        fi
      fi
    done
  fi

  # Run the query outside the `if` below, where a failed query would read as a
  # missing column.
  set +e
  marker_column="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" information_schema -N -s -e \
    "SELECT 1 \
     FROM COLUMNS \
     WHERE TABLE_SCHEMA = '$(sql_escape "$db_name")' \
       AND TABLE_NAME = 'db_version' \
       AND COLUMN_NAME = 'content_$latest_update';")"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    cmangos_fail "Failed to read the content version of the world database. See the error above."
  fi

  if ! grep -Fxq "1" <<<"$marker_column"; then
    if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -e \
      "ALTER TABLE db_version ADD COLUMN \`content_$latest_update\` bit DEFAULT NULL;"; then
      cmangos_fail "Failed to update the content version of the world database. See the error above."
    fi
  fi
}

apply_world_content_updates() {
  local world_db="$1"

  apply_tracked_sql_dir "$world_db" "/sql/database/Updates" "database-updates"
  set_latest_content_version_marker "$world_db"
  apply_tracked_sql_dir "$world_db" "/sql/database/Updates/Instances" "database-instance-updates"
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
  local realm_port
  local realm_icon
  local realm_timezone
  local realm_allowed_security_level

  realm_name="$(sql_escape "$CMANGOS_REALMLIST_NAME")"
  realm_address="$(sql_escape "$CMANGOS_REALMLIST_ADDRESS")"
  realm_port="$(sql_escape "$CMANGOS_REALMLIST_PORT")"
  realm_icon="$(sql_escape "$CMANGOS_REALMLIST_ICON")"
  realm_timezone="$(sql_escape "$CMANGOS_REALMLIST_TIMEZONE")"
  realm_allowed_security_level="$(sql_escape "$CMANGOS_REALMLIST_ALLOWED_SECURITY_LEVEL")"
  cmangos_log "Configuring the '$CMANGOS_REALMLIST_NAME' realm..."

  if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "realmd" -e \
    "INSERT INTO \`realmlist\` \
       (\`id\`, \`name\`, \`address\`, \`port\`, \`icon\`, \`timezone\`, \`allowedSecurityLevel\`) \
     VALUES \
       (1, '$realm_name', '$realm_address', '$realm_port', '$realm_icon', '$realm_timezone', '$realm_allowed_security_level') \
     ON DUPLICATE KEY UPDATE \
       \`name\` = VALUES(\`name\`), \
       \`address\` = VALUES(\`address\`), \
       \`port\` = VALUES(\`port\`), \
       \`icon\` = VALUES(\`icon\`), \
       \`timezone\` = VALUES(\`timezone\`), \
       \`allowedSecurityLevel\` = VALUES(\`allowedSecurityLevel\`);"; then
    cmangos_fail "Failed to configure the '$CMANGOS_REALMLIST_NAME' realm. See the error above."
  fi
}

ensure_maintenance_db_exists() {
  create_database "maintenance" true
  grant_permissions "maintenance" true

  if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -e \
    "CREATE TABLE IF NOT EXISTS \`migration_corrections\` ( \
      \`db_name\` VARCHAR(64) NOT NULL, \
      \`commit_hash\` CHAR(40) NOT NULL, \
      \`acknowledged_at\` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP, \
      PRIMARY KEY (\`db_name\`, \`commit_hash\`) \
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"; then
    cmangos_fail "Failed to set up the record of confirmed migration edits in the 'maintenance' database. See the error above."
  fi

  # Rewrite the rows that older images keyed by the database name, `mangos`.
  # TODO: Remove this once it is reasonable to assume that every existing
  # installation has received this change.
  if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -e \
    "UPDATE IGNORE \`migration_corrections\` SET \`db_name\` = 'world' \
     WHERE \`db_name\` = 'mangos';"; then
    cmangos_fail "Failed to set up the record of confirmed migration edits in the 'maintenance' database. See the error above."
  fi
}

correction_acknowledged() {
  local db_name="$1"
  local commit_hash="$2"
  local count
  local status

  set +e
  count="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -N -s -e \
    "SELECT COUNT(*) FROM \`migration_corrections\` \
    WHERE \`db_name\` = '$(sql_escape "$db_name")' \
    AND \`commit_hash\` = '$(sql_escape "$commit_hash")';")"
  status=$?
  set -e

  # Callers use this as a condition, where `set -e` does not apply, so check
  # the query status by hand.
  if [[ $status -ne 0 ]]; then
    cmangos_fail "Failed to read the record of confirmed migration edits in the 'maintenance' database. See the error above."
  fi

  [[ "$count" -gt 0 ]]
}

acknowledge_correction() {
  local db_name="$1"
  local commit_hash="$2"

  if ! mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -e \
    "INSERT IGNORE INTO \`migration_corrections\` (\`db_name\`, \`commit_hash\`) \
    VALUES ('$(sql_escape "$db_name")', '$(sql_escape "$commit_hash")');"; then
    cmangos_fail "Failed to update the record of confirmed migration edits in the 'maintenance' database. See the error above."
  fi
}

# The GitHub repository of a migration edit source.
correction_source_repository() {
  local source_name="$1"

  case "$source_name" in
    core) printf 'cmangos/mangos-%s' "$CMANGOS_EXPANSION" ;;
    db) printf 'cmangos/%s-db' "$CMANGOS_EXPANSION" ;;
    playerbots) printf 'cmangos/playerbots' ;;
    *) cmangos_fail "The list of migration edits in this image is damaged (unknown source '$source_name'). Report it:
https://github.com/mserajnik/cmangos-deploy/issues" ;;
  esac
}

# Reads `/sql/migration-edits`, which the build writes from
# `CMANGOS_MIGRATION_EDITS`, into the `MIGRATION_EDIT_*` arrays, one element
# per edit. The value is `<target>:<source>@<commit>[,<source>@<commit>]...`
# entries separated by `|`. A manual build leaves the file empty.
parse_migration_edits() {
  MIGRATION_EDIT_TARGETS=()
  MIGRATION_EDIT_SOURCES=()
  MIGRATION_EDIT_COMMITS=()

  local file="/sql/migration-edits"
  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local raw
  raw="$(head -n1 "$file" | tr -d '\r\n')"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"

  if [[ -z "$raw" ]]; then
    return 0
  fi

  local entry target sources token
  local entries=() tokens=()

  IFS='|' read -r -a entries <<<"$raw"
  for entry in "${entries[@]}"; do
    if [[ "$entry" != *:* ]]; then
      cmangos_fail "The list of migration edits in this image is damaged ('$entry'). Report it:
https://github.com/mserajnik/cmangos-deploy/issues"
    fi
    target="${entry%%:*}"
    sources="${entry#*:}"

    IFS=',' read -r -a tokens <<<"$sources"
    for token in "${tokens[@]}"; do
      if [[ "$token" != *@* ]]; then
        cmangos_fail "The list of migration edits in this image is damaged ('$token'). Report it:
https://github.com/mserajnik/cmangos-deploy/issues"
      fi
      MIGRATION_EDIT_TARGETS+=("$target")
      MIGRATION_EDIT_SOURCES+=("${token%%@*}")
      MIGRATION_EDIT_COMMITS+=("${token#*@}")
    done
  done
}

# Re-creates the world database from the image's SQL, which already contains
# every migration edit. Changes made directly in the world database are lost.
recreate_world_database() {
  local full_world_dump
  full_world_dump="$(get_full_world_dump_file)"

  if [[ -z "$full_world_dump" ]]; then
    cmangos_fail "This image has no full world dump, so it cannot re-create the world database. The world database is unchanged. Report it:
https://github.com/mserajnik/cmangos-deploy/issues"
  fi

  drop_database "mangos"
  create_database "mangos"
  grant_permissions "mangos"

  import_dump "mangos" "/sql/core/base/mangos.sql"
  import_dump "mangos" "$full_world_dump"

  apply_world_content_updates "mangos"
  apply_versioned_updates "mangos" "/sql/core/updates/mangos" "mangos"
  apply_world_static_sql "mangos"
}

PENDING_DB_NAMES=()
PENDING_DB_SOURCES=()
PENDING_DB_COMMIT_HASHES=()

# One re-creation applies every pending world edit at once.
process_world_corrections() {
  local i
  local pending=()

  for i in "${!MIGRATION_EDIT_TARGETS[@]}"; do
    if [[ "${MIGRATION_EDIT_TARGETS[i]}" = "world" ]] &&
      ! correction_acknowledged "world" "${MIGRATION_EDIT_COMMITS[i]}"; then
      pending+=("$i")
    fi
  done

  if [[ "${#pending[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ "${CMANGOS_ENABLE_AUTOMATIC_WORLD_DB_CORRECTIONS:-0}" = "1" ]]; then
    cmangos_log "Re-creating the world database to apply the migration edits..."
    recreate_world_database
    for i in "${pending[@]}"; do
      acknowledge_correction "world" "${MIGRATION_EDIT_COMMITS[i]}"
    done
    return 0
  fi

  if [[ "${CMANGOS_HALT_ON_MIGRATION_EDITS:-0}" = "1" ]]; then
    for i in "${pending[@]}"; do
      PENDING_DB_NAMES+=("world")
      PENDING_DB_SOURCES+=("${MIGRATION_EDIT_SOURCES[i]}")
      PENDING_DB_COMMIT_HASHES+=("${MIGRATION_EDIT_COMMITS[i]}")
    done
    return 0
  fi

  # Leave the edit unacknowledged. The warning then repeats every time the
  # container starts.
  local repository
  for i in "${pending[@]}"; do
    repository="$(correction_source_repository "${MIGRATION_EDIT_SOURCES[i]}")"
    cmangos_log "WARNING: The world database has a migration edit ($repository@${MIGRATION_EDIT_COMMITS[i]:0:7}), but both 'CMANGOS_ENABLE_AUTOMATIC_WORLD_DB_CORRECTIONS' and 'CMANGOS_HALT_ON_MIGRATION_EDITS' are disabled. The 'database' service does not halt, and the world database stays in an inconsistent state. The 'mangosd' service may misbehave or fail to start." >&2
  done
}

# The MariaDB database of a migration edit target.
correction_database_name() {
  local db_name="$1"

  case "$db_name" in
    world) printf 'mangos' ;;
    characters) printf 'characters' ;;
    realmd) printf 'realmd' ;;
    logs) printf 'logs' ;;
    *) cmangos_fail "The list of migration edits in this image is damaged (unknown target '$db_name'). Report it:
https://github.com/mserajnik/cmangos-deploy/issues" ;;
  esac
}

# A database with user state cannot be re-created. The user applies its edits
# by hand and confirms.
process_userstate_corrections() {
  local i db_name source_name commit_hash repository database_name

  for i in "${!MIGRATION_EDIT_TARGETS[@]}"; do
    db_name="${MIGRATION_EDIT_TARGETS[i]}"
    source_name="${MIGRATION_EDIT_SOURCES[i]}"
    commit_hash="${MIGRATION_EDIT_COMMITS[i]}"

    if [[ "$db_name" = "world" ]] ||
      correction_acknowledged "$db_name" "$commit_hash"; then
      continue
    fi

    if [[ "${CMANGOS_HALT_ON_MIGRATION_EDITS:-0}" = "1" ]]; then
      PENDING_DB_NAMES+=("$db_name")
      PENDING_DB_SOURCES+=("$source_name")
      PENDING_DB_COMMIT_HASHES+=("$commit_hash")
      continue
    fi

    # Leave the edit unacknowledged. The warning then repeats every time the
    # container starts.
    repository="$(correction_source_repository "$source_name")"
    database_name="$(correction_database_name "$db_name")"
    cmangos_log "WARNING: The '$database_name' database has a migration edit ($repository@${commit_hash:0:7}), but 'CMANGOS_HALT_ON_MIGRATION_EDITS' is disabled. The 'database' service does not halt, and the '$database_name' database stays in an inconsistent state." >&2
  done
}

print_correction_halt_message() {
  cat >&2 <<'EOF'
[cmangos-deploy]: ERROR: Migration edits affect your databases.
cmangos-deploy does not handle these edits for you. CMaNGOS does not start
until you handle them and confirm, as described below.

The edits, each with the name of the database it affects:
EOF

  local i=0
  local name
  local source_name
  local commit_hash
  local repository
  local database_name
  while [[ "$i" -lt "${#PENDING_DB_NAMES[@]}" ]]; do
    name="${PENDING_DB_NAMES[$i]}"
    source_name="${PENDING_DB_SOURCES[$i]}"
    commit_hash="${PENDING_DB_COMMIT_HASHES[$i]}"
    repository="$(correction_source_repository "$source_name")"
    database_name="$(correction_database_name "$name")"
    printf '  - %s\n' "$database_name" >&2
    printf '    https://github.com/%s/commit/%s\n' "$repository" "$commit_hash" >&2
    i=$((i + 1))
  done

  cat >&2 <<'EOF'

The SQL you run changes your databases directly. If something goes wrong, only
a backup from before the update can restore them. The restore needs the
'database' service to run normally, so confirm first, then restore the backup
as the documentation describes.

For each edit above:

  1. Open its GitHub link to see what changed.
  2. Make the edit's changes yourself in the affected database. The 'database'
     service does not apply an edited migration again, so the database still
     matches the result of the old version. Run the SQL that changes it to the
     result of the new version.

     To open the database, run on the host:

       docker compose exec database mariadb -u root -p <database>

     (The MariaDB client prompts for the password, which is
     'MARIADB_ROOT_PASSWORD' from your 'compose.yaml'. To leave the client, run
     'exit'.)

     You can ignore an edit to a migration that has not been applied to the
     database yet. The documentation shows how to check:
     https://github.com/mserajnik/cmangos-deploy/blob/master/docs/usage.md#applying-changes-by-hand

When you have handled every edit above, confirm by running on the host:

  docker compose exec database cmangos-confirm-changes

To stop the containers and handle the edits later, run on the host:

  docker compose down

Until you confirm, MariaDB is reachable only inside the container, through its
socket, and not on port 3306.

Note: When you confirm, cmangos-deploy treats the listed commits as applied. It
does not check your databases to verify that the changes you made match what
the commits describe. If your manual fix is incorrect or incomplete, the
affected database is left in an inconsistent state and CMaNGOS may fail to
start. The responsibility for matching what the commits do is yours, and
cmangos-deploy provides no further support for individual cases.
EOF
}

wait_for_change_ack() {
  touch /tmp/cmangos-changes-pending

  while [[ ! -f /tmp/cmangos-changes-acknowledged ]]; do
    sleep 5
  done

  rm -f /tmp/cmangos-changes-pending

  # `cmangos-confirm-changes` waits for the receipt, because the next container
  # start deletes the acknowledgement too.
  mv /tmp/cmangos-changes-acknowledged /tmp/cmangos-changes-consumed
}

process_custom_sql() {
  local file_directory="$1"
  local sql_file
  local sql_files=()
  local sql_files_raw
  local status

  if [[ ! -d "$file_directory" ]]; then
    cmangos_log "WARNING: The custom SQL file directory '$file_directory' does not exist. Mount your custom SQL directory there in your 'compose.yaml', as the example Compose file shows, or set 'CMANGOS_PROCESS_CUSTOM_SQL' to '0'." >&2
    return 0
  fi

  if [[ ! -r "$file_directory" ]] || [[ ! -x "$file_directory" ]]; then
    cmangos_fail "The custom SQL file directory '$file_directory' is not readable by the 'mysql' user (UID $(id -u)). This is a permission problem on the host: the bind-mounted directory must be readable by that user. Adjust the permissions, then run 'docker compose up -d' on the host."
  fi

  # Check `find` on its own, so a failure says which step failed. The names are
  # passed through a file, because a command substitution drops NUL bytes.
  sql_files_raw="$(mktemp)"
  set +e
  find "$file_directory" -type f -name '*.sql' -print0 >"$sql_files_raw"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    rm -f "$sql_files_raw"
    cmangos_fail "Failed to list the custom SQL files in '$file_directory'. See the error above."
  fi

  set +e
  sort -z -o "$sql_files_raw" "$sql_files_raw"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    rm -f "$sql_files_raw"
    cmangos_fail "Failed to sort the custom SQL file listing in '$file_directory'. See the error above."
  fi

  mapfile -d '' -t sql_files <"$sql_files_raw"
  rm -f "$sql_files_raw"

  case "${#sql_files[@]}" in
    0) cmangos_log "Found no custom SQL files to process." ;;
    1) cmangos_log "Found 1 custom SQL file to process." ;;
    *) cmangos_log "Found ${#sql_files[@]} custom SQL files to process." ;;
  esac

  for sql_file in "${sql_files[@]}"; do
    cmangos_log "Processing the custom SQL file '$(basename "$sql_file")'..."

    if ! import_sql_file "mangos" "$sql_file"; then
      cmangos_log "ERROR: Failed to process the custom SQL file '$(basename "$sql_file")'. See the error above." >&2
    fi
  done
}
