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

# A data directory with the first marker is from a first start that did not
# finish.
INITIALIZING_MARKER="/var/lib/mysql/.cmangos-deploy-initializing"
INITIALIZED_MARKER="/var/lib/mysql/.cmangos-deploy-initialized"

mark_initializing() {
  touch "$INITIALIZING_MARKER"
}

mark_initialized() {
  mv "$INITIALIZING_MARKER" "$INITIALIZED_MARKER"
}

# A data directory from before the markers counts as set up when its world
# database holds data.
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

  cmangos_fail "The databases are not set up completely. If this is a new installation, remove the database volume and start again. Otherwise the volume holds your characters: remove it only if you have a backup, and restore the backup after the new start:
https://github.com/mserajnik/cmangos-deploy/blob/master/docs/usage.md#restoring-a-backup"
}

create_database() {
  local db_name="$1"
  local silent="${2:-false}"

  if [[ "$silent" = false ]]; then
    cmangos_log "Creating database '$db_name'..."
  fi

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e \
    "CREATE DATABASE IF NOT EXISTS \`$db_name\` DEFAULT CHARSET utf8 COLLATE utf8_general_ci;"
}

drop_database() {
  local db_name="$1"
  local silent="${2:-false}"

  if [[ "$silent" = false ]]; then
    cmangos_log "Dropping database '$db_name'..."
  fi

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e \
    "DROP DATABASE IF EXISTS \`$db_name\`;"
}

grant_permissions() {
  local db_name="$1"
  local silent="${2:-false}"
  local user
  local password

  if [[ "$silent" = false ]]; then
    cmangos_log "Granting permissions to database user '$MARIADB_USER' for database '$db_name'..."
  fi

  user="$(sql_escape "$MARIADB_USER")"
  password="$(sql_escape "$MARIADB_PASSWORD")"

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" -e \
    "CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$password'; \
    GRANT ALL ON \`$db_name\`.* TO '$user'@'%'; \
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

# The name of the table in each database that records the applied SQL files,
# keyed by `<prefix>/<filename>`.
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
    cmangos_fail "Failed to check which SQL files the '$db_name' database has applied. See the error above."
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
    cmangos_log "Skipping already applied SQL '$description' for database '$db_name'."
    return 0
  fi

  cmangos_log "Applying tracked SQL '$description' to database '$db_name'..."
  table_name="$(tracking_table_name)"
  escaped_key="$(sql_escape "$sql_key")"
  # The file and its record share one session, so a stop cannot fall between
  # them. The `mariadb` client stops at the first failed statement, which
  # leaves a failed file unrecorded.
  {
    cat "$file"
    echo
    echo "INSERT INTO \`$db_name\`.\`$table_name\` (\`sql_key\`) VALUES ('$escaped_key')" \
      "ON DUPLICATE KEY UPDATE \`applied_at\` = \`applied_at\`;"
  } | mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name"
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
    cmangos_fail "Failed to list SQL files in '$dir'."
  fi

  set +e
  sort -z -o "$listing" "$listing"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    rm -f "$listing"
    cmangos_fail "Failed to sort the SQL file listing in '$dir'."
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
      cmangos_fail "Unsupported database kind '$db_kind'."
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
    cmangos_fail "Failed to read the required version for database '$db_name'."
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
    cmangos_fail "Failed to list versioned updates in '$update_dir'."
  fi

  update_files="$(sort <<<"$update_files")"

  current_version="$(get_current_required_version "$db_name" "$db_kind")"

  if [[ -z "$current_version" ]]; then
    cmangos_log "The '$db_name' database has no required version yet. Applying all '$db_kind' updates."
    current_rev=0
  else
    current_rev="$(parse_update_rev "$current_version")"
    cmangos_log "Current required version for '$db_name' is '$current_version'."
  fi

  while read -r update_file; do
    [[ -n "$update_file" ]] || continue

    update_name="$(basename "$update_file" .sql)"
    update_rev="$(parse_update_rev "$update_name")"

    if [[ "$update_rev" -gt "$current_rev" ]]; then
      cmangos_log "Applying versioned SQL '$update_name' to database '$db_name'..."
      import_sql_file "$db_name" "$update_file"
      applied_count=$((applied_count + 1))
    fi
  done <<<"$update_files"

  if [[ "$applied_count" -eq 0 ]]; then
    cmangos_log "No new versioned updates found for database '$db_name'."
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
    cmangos_fail "Failed to list full world dumps in '/sql/database/Full_DB'."
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
    cmangos_fail "Failed to list content updates in '/sql/database/Updates'."
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
    cmangos_fail "Failed to read the content version of the '$db_name' database. See the error above."
  fi

  if [[ -n "$existing_columns" ]]; then
    printf '%s\n' "$existing_columns" | while read -r column_name; do
      [[ -n "$column_name" ]] || continue

      if [[ "$column_name" != "content_$latest_update" ]]; then
        mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$db_name" -e \
          "ALTER TABLE db_version DROP COLUMN \`$column_name\`;"
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
    cmangos_fail "Failed to read the content version of the '$db_name' database. See the error above."
  fi

  if ! grep -Fxq "1" <<<"$marker_column"; then
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

# Works around upstream: `tbc-db/locales/OtherLocales.sql` re-creates
# `locales_gameobject` with the columns from before `s2485`, which `mangosd` no
# longer reads, so apply `s2485` again while `castbarcaption_loc1` exists. A
# partial upstream fix makes the `ALTER` statements fail, which stops the
# start.
# TODO: Remove this and its calls once the drift check on that file in
# `.github/deploy.yaml` reports the fix.
fix_tbc_locales_gameobject() {
  local world_db="$1"
  local has_old_column
  local status

  if [[ "$CMANGOS_EXPANSION" != "tbc" ]]; then
    return 0
  fi

  set +e
  has_old_column="$(mariadb -u root -p"$MARIADB_ROOT_PASSWORD" information_schema -N -s -e \
    "SELECT 1 \
     FROM COLUMNS \
     WHERE TABLE_SCHEMA = '$(sql_escape "$world_db")' \
       AND TABLE_NAME = 'locales_gameobject' \
       AND COLUMN_NAME = 'castbarcaption_loc1' \
     LIMIT 1;")"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    cmangos_fail "Failed to check the columns of 'locales_gameobject' in '$world_db'. See the error above."
  fi

  if [[ -z "$has_old_column" ]]; then
    return 0
  fi

  cmangos_log "Re-applying the s2485 changes to 'locales_gameobject' on '$world_db' (upstream tbc-db bug workaround)..."
  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$world_db" <<'SQL'
ALTER TABLE `locales_gameobject` CHANGE `name_loc1` `name_loc1` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `name_loc2` `name_loc2` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `name_loc3` `name_loc3` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `name_loc4` `name_loc4` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `name_loc5` `name_loc5` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `name_loc6` `name_loc6` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `name_loc7` `name_loc7` varchar(100);
ALTER TABLE `locales_gameobject` CHANGE `name_loc8` `name_loc8` varchar(100);
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
  cmangos_log "Configuring realm '$CMANGOS_REALMLIST_NAME'..."

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "realmd" -e \
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;"

  # Rewrite the rows that older images keyed by the database name, `mangos`.
  # TODO: Remove this once it is reasonable to assume that every existing
  # installation has received this change.
  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -e \
    "UPDATE IGNORE \`migration_corrections\` SET \`db_name\` = 'world' \
     WHERE \`db_name\` = 'mangos';"
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
    cmangos_fail "Failed to read which migration edits the databases have applied. See the error above."
  fi

  [[ "$count" -gt 0 ]]
}

acknowledge_correction() {
  local db_name="$1"
  local commit_hash="$2"

  mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "maintenance" -e \
    "INSERT IGNORE INTO \`migration_corrections\` (\`db_name\`, \`commit_hash\`) \
    VALUES ('$(sql_escape "$db_name")', '$(sql_escape "$commit_hash")');"
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
  fix_tbc_locales_gameobject "mangos"
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

  # Leave the edit unacknowledged. The warning then repeats on every start.
  local repository
  for i in "${pending[@]}"; do
    repository="$(correction_source_repository "${MIGRATION_EDIT_SOURCES[i]}")"
    cmangos_log "WARNING: The world database has a migration edit ($repository@${MIGRATION_EDIT_COMMITS[i]:0:7}), but both 'CMANGOS_ENABLE_AUTOMATIC_WORLD_DB_CORRECTIONS' and 'CMANGOS_HALT_ON_MIGRATION_EDITS' are disabled. The start continues, and the world database stays out of step with this image. The server may misbehave or fail to start." >&2
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

    # Leave the edit unacknowledged. The warning then repeats on every start.
    repository="$(correction_source_repository "$source_name")"
    database_name="$(correction_database_name "$db_name")"
    cmangos_log "WARNING: The '$database_name' database has a migration edit ($repository@${commit_hash:0:7}), but 'CMANGOS_HALT_ON_MIGRATION_EDITS' is disabled. The start continues, and the database stays out of step with this image." >&2
  done
}

print_correction_abort_message() {
  cat >&2 <<'EOF'
[cmangos-deploy]: ERROR: Migration edits affect your databases.
cmangos-deploy will not apply these changes for you. Startup is halted.

Affected databases, one entry per edit:
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
    printf '  - %s (%s)\n' "$name" "$database_name" >&2
    printf '    https://github.com/%s/commit/%s\n' "$repository" "$commit_hash" >&2
    i=$((i + 1))
  done

  cat >&2 <<'EOF'

For each entry above:

  1. Open its GitHub link to see what changed.
  2. Apply the equivalent SQL to the running database yourself, using the name
     in parentheses above:
       docker compose exec database mariadb -u root -p <database>
     (mariadb prompts for the password, which matches your
     'MARIADB_ROOT_PASSWORD' setting in your 'compose.yaml'.)

When you have applied the changes to all of them, confirm by running on the
host:
  docker compose exec database cmangos-confirm-changes

To abort instead, run on the host:
  docker compose down

While the container is paused, MariaDB is reachable inside the container via
the internal socket. TCP access on port 3306 is not available during the pause.
CMaNGOS stays offline until you confirm or abort, so take as long as you
need.

Note: When you confirm, cmangos-deploy treats the listed commits as applied
and continues. It does not check your database to verify that the changes you
made match what the commits describe. If your manual fix is incorrect or
incomplete, the database will be in an inconsistent state and CMaNGOS may
fail to start. The responsibility for matching what the commits do is yours,
and cmangos-deploy provides no further support for resolving these issues.
EOF
}

wait_for_change_ack() {
  touch /tmp/cmangos-changes-pending

  while [[ ! -f /tmp/cmangos-changes-acknowledged ]]; do
    sleep 5
  done

  rm -f /tmp/cmangos-changes-pending

  # `cmangos-confirm-changes` waits for the receipt, because a later start
  # deletes the acknowledgement too.
  mv /tmp/cmangos-changes-acknowledged /tmp/cmangos-changes-consumed
}

process_custom_sql() {
  local file_directory="$1"
  local sql_file
  local sql_files=()
  local sql_files_raw
  local status

  if [[ ! -d "$file_directory" ]]; then
    cmangos_log "WARNING: The custom SQL file directory '$file_directory' does not exist." >&2
    return 0
  fi

  if [[ ! -r "$file_directory" ]] || [[ ! -x "$file_directory" ]]; then
    cmangos_fail "The custom SQL file directory '$file_directory' is not readable by the database user (UID $(id -u)). This is a permission problem on the host: the bind-mounted directory must be readable by that user. Adjust the permissions, then restart."
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
    cmangos_fail "Failed to list custom SQL files in '$file_directory'."
  fi

  set +e
  sort -z -o "$sql_files_raw" "$sql_files_raw"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    rm -f "$sql_files_raw"
    cmangos_fail "Failed to sort the custom SQL file listing in '$file_directory'."
  fi

  mapfile -d '' -t sql_files <"$sql_files_raw"
  rm -f "$sql_files_raw"

  cmangos_log "Found ${#sql_files[@]} custom SQL file(s) to process."

  for sql_file in "${sql_files[@]}"; do
    cmangos_log "Processing custom SQL file '$(basename "$sql_file")'..."

    if ! import_sql_file "mangos" "$sql_file"; then
      cmangos_log "ERROR: Failed to process custom SQL file '$(basename "$sql_file")'." >&2
    fi
  done
}
