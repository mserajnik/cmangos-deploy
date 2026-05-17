#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Confirms manually applied migration edits so `update-db.sh` can continue.
# Refuses to run unless the pending sentinel exists, so accidental invocations
# during normal operation are no-ops.

set -eu

if [ ! -f /tmp/cmangos-changes-pending ]; then
  echo "[cmangos-deploy]: ERROR: cmangos-deploy is not currently waiting for confirmation. Nothing to do." >&2
  exit 1
fi

touch /tmp/cmangos-changes-acknowledged

# `docker compose exec` defaults to root, but the bootstrap runs as the
# database user and removes both sentinels when it sees the ack. Match
# ownership to the pending sentinel so the bootstrap can remove the ack file
# from sticky `/tmp`.
chown --reference=/tmp/cmangos-changes-pending /tmp/cmangos-changes-acknowledged

echo "[cmangos-deploy]: Confirmation recorded; startup will continue."
