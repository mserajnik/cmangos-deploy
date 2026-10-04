# shellcheck shell=sh

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Assigns the UID and GID from `CMANGOS_UID` and `CMANGOS_GID` to the `cmangos`
# user, then runs the sourcing wrapper again as that user.

if [ "$(id -u)" = "0" ]; then
  uid="${CMANGOS_UID:-1000}"
  gid="${CMANGOS_GID:-1000}"

  # `usermod` also changes the owner of the files in the home directory. The
  # bind mounts keep their owner, so the UID and GID have to match it.
  if [ "$(id -g cmangos)" != "$gid" ]; then
    # `-o` accepts a GID that a group in the image already uses, such as `100`.
    groupmod -o -g "$gid" cmangos
  fi
  if [ "$(id -u cmangos)" != "$uid" ]; then
    usermod -u "$uid" cmangos
  fi

  export HOME=/home/cmangos CMANGOS_PRIVILEGES_DROPPED=1
  exec setpriv --reuid="$uid" --regid="$gid" --clear-groups --inh-caps=-all "$0" "$@"
elif [ -z "${CMANGOS_PRIVILEGES_DROPPED:-}" ]; then
  echo "[cmangos-deploy]: ERROR: The container has to start as root. Replace 'user' with 'CMANGOS_UID' and 'CMANGOS_GID' in its service in your 'compose.yaml', as the 'compose-*.yaml.example' files show." >&2
  exit 1
fi
