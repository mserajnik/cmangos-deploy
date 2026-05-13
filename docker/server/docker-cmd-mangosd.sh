#!/bin/sh

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

# Container command wrapper for the `mangosd` binary. Drops privileges via
# `fixuid`, validates the bind-mounted config files, warns about deprecated
# `WAIT_*` environment variables, and launches `mangosd`.

set -eu

eval "$(fixuid -q)"

config_dir="/opt/cmangos/config"
required_files="
  mangosd.conf
  anticheat.conf
  ahbot.conf
  aiplayerbot.conf
"

if [ "${CMANGOS_EXPANSION:-}" = "classic" ]; then
  required_files="$required_files
  mods.conf
"
fi

for config_name in $required_files; do
  config_file="$config_dir/$config_name"

  if [ ! -f "$config_file" ]; then
    echo "[cmangos-deploy]: ERROR: Configuration file '$config_file' is missing, exiting." >&2
    exit 1
  fi
done

if [ -n "${WAIT_HOSTS:-}" ] || [ -n "${WAIT_TIMEOUT:-}" ]; then
  echo "[cmangos-deploy]: WARNING: The 'WAIT_HOSTS' and 'WAIT_TIMEOUT' environment variables are deprecated and have no effect. The server containers wait for the database via Docker Compose's 'depends_on: condition: service_healthy' instead. Remove these variables from your Compose configuration. After 2026-08-31, cmangos-deploy will fail to start if these are still set." >&2
fi

exec /opt/cmangos/bin/mangosd -c "$config_dir/mangosd.conf"
