#!/bin/sh

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Runs the client data extractors. `--force` skips the prompt about existing
# data.

set -eu

# shellcheck source=docker/check-deploy-version.sh
. /usr/local/lib/cmangos-deploy/check-deploy-version.sh
# shellcheck source=docker/server/drop-privileges.sh
. /usr/local/lib/cmangos-deploy/drop-privileges.sh

client_data_dir="/opt/cmangos/storage/client-data"
extracted_data_dir="/opt/cmangos/storage/data"
tools_dir="/opt/cmangos/bin/tools"

force=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    -f | --force)
      force=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ ! -d "$client_data_dir" ] || [ ! -d "$client_data_dir/Data" ]; then
  echo "[cmangos-deploy]: ERROR: '$client_data_dir' has no 'Data' directory. Copy the contents of your client directory there." >&2
  exit 1
fi

if [ ! -d "$extracted_data_dir" ]; then
  echo "[cmangos-deploy]: ERROR: The extracted data directory '$extracted_data_dir' does not exist. Mount your extracted data directory there in your 'compose.yaml', as the 'compose-*.yaml.example' files show." >&2
  exit 1
fi

if [ "$force" = false ]; then
  if [ -d "$extracted_data_dir/dbc" ] || [ -d "$extracted_data_dir/maps" ] || [ -d "$extracted_data_dir/mmaps" ] || [ -d "$extracted_data_dir/vmaps" ]; then
    echo "[cmangos-deploy]: Previously extracted data has been found in '$extracted_data_dir'. Continue with the extraction, which will overwrite the old data? [Y/n]"

    if ! read -r choice; then
      choice="y"
    fi
    choice=$(echo "${choice:-y}" | tr -d '[:space:]')
    if [ "$choice" = "n" ] || [ "$choice" = "N" ]; then
      echo "[cmangos-deploy]: The old data stays in place."
      exit 1
    fi
  fi
fi

cd "$client_data_dir"

# Remove the output of an earlier run.
rm -rf ./Buildings ./Cameras ./CreatureModels ./dbc ./maps ./mmaps ./vmaps
rm -f ./MaNGOSExtractor.log ./MaNGOSExtractor_detailed.log

cd "$tools_dir"
if ! ./ExtractResources.sh a "$client_data_dir" "$client_data_dir"; then
  echo "[cmangos-deploy]: ERROR: The extraction failed. See the errors above and 'MaNGOSExtractor_detailed.log' in the client data directory." >&2
  exit 1
fi

cd "$client_data_dir"

# Remove what the server does not need.
rm -rf ./Buildings
rm -f ./MaNGOSExtractor.log ./MaNGOSExtractor_detailed.log

# Replace only what the extractors produce, so files such as `.gitkeep` stay.
# `mangosd` reads the M2 files in `Cameras/` and, for WotLK, `CreatureModels/`.
rm -rf \
  "$extracted_data_dir/Buildings" \
  "$extracted_data_dir/Cameras" \
  "$extracted_data_dir/CreatureModels" \
  "$extracted_data_dir/dbc" \
  "$extracted_data_dir/maps" \
  "$extracted_data_dir/mmaps" \
  "$extracted_data_dir/vmaps"
rm -f \
  "$extracted_data_dir/MaNGOSExtractor.log" \
  "$extracted_data_dir/MaNGOSExtractor_detailed.log"

# `dbc/` moves last. After an interrupted move, the DBC files are missing, and
# the server refuses to start.
if [ -d ./CreatureModels ]; then
  mv ./CreatureModels "$extracted_data_dir/"
fi
mv ./Cameras ./maps ./mmaps ./vmaps ./dbc "$extracted_data_dir/"
