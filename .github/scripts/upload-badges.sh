#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Generates the badge JSON files and uploads them via FTP to the static host
# that serves the README badges.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

if [[ -z "${BADGES_FTP_HOST:-}" || -z "${BADGES_FTP_USERNAME:-}" || -z "${BADGES_FTP_PASSWORD:-}" ]]; then
  echo "Badge FTP secrets are missing, skipping upload."
  exit 0
fi

require_env CLASSIC_TAG
require_env TBC_TAG
require_env WOTLK_TAG

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat >classic-build-badge.json <<EOF
{
  "schemaVersion": 1,
  "label": "Latest CMaNGOS Classic build",
  "message": "$CLASSIC_TAG",
  "color": "blue"
}
EOF

cat >tbc-build-badge.json <<EOF
{
  "schemaVersion": 1,
  "label": "Latest CMaNGOS TBC build",
  "message": "$TBC_TAG",
  "color": "blue"
}
EOF

cat >wotlk-build-badge.json <<EOF
{
  "schemaVersion": 1,
  "label": "Latest CMaNGOS WotLK build",
  "message": "$WOTLK_TAG",
  "color": "blue"
}
EOF

cat >date-badge.json <<EOF
{
  "schemaVersion": 1,
  "label": "Latest build date",
  "message": "$timestamp",
  "color": "orange"
}
EOF

curl --fail --silent --show-error \
  -T "{classic-build-badge.json,tbc-build-badge.json,wotlk-build-badge.json,date-badge.json}" \
  --user "$BADGES_FTP_USERNAME:$BADGES_FTP_PASSWORD" \
  "ftp://$BADGES_FTP_HOST/"
