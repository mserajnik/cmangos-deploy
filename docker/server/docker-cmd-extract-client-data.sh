#!/bin/sh

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Container command wrapper that runs the client data extractors. Skips the
# confirmation prompt when `--force` is passed.

set -eu

eval "$(fixuid -q)"

client_data_dir="/opt/cmangos/storage/client-data"
extracted_data_dir="/opt/cmangos/storage/data"
tools_dir="/opt/cmangos/bin/tools"
extractor_script="$tools_dir/ExtractResources.sh"

# The `--force` flag can be used to skip the confirmation prompt when
# previously extracted data is found. This is particularly useful for
# automation where the user is not able to interact with the prompt.
force=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    -f | --force)
      # If user passes `-f` or `--force`, set 'force' to true.
      force=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ ! -f "$extractor_script" ]; then
  echo "[cmangos-deploy]: ERROR: Extractors are not available in this image." >&2
  echo "[cmangos-deploy]: On arm64 this is expected because upstream forces BUILD_EXTRACTORS=OFF." >&2
  echo "[cmangos-deploy]: Use an amd64 image, e.g. with '--platform linux/amd64'." >&2
  exit 1
fi

if [ ! -d "$client_data_dir" ] || [ ! -d "$client_data_dir/Data" ]; then
  echo "[cmangos-deploy]: ERROR: Client data not found in '$client_data_dir', aborting extraction." >&2
  exit 1
fi

if [ ! -d "$extracted_data_dir" ]; then
  echo "[cmangos-deploy]: ERROR: Extracted data target directory '$extracted_data_dir' does not exist, aborting extraction." >&2
  exit 1
fi

if [ "$force" = false ]; then
  if [ -d "$extracted_data_dir/dbc" ] || [ -d "$extracted_data_dir/maps" ] || [ -d "$extracted_data_dir/mmaps" ] || [ -d "$extracted_data_dir/vmaps" ]; then
    echo "[cmangos-deploy]: Previously extracted data has been found in '$extracted_data_dir'; continue with the extraction (which will overwrite the old data)? [Y/n]"

    if ! read -r choice; then
      choice="y"
    fi
    choice=$(echo "${choice:-y}" | tr -d '[:space:]')
    if [ "$choice" = "n" ] || [ "$choice" = "N" ]; then
      echo "[cmangos-deploy]: Aborting extraction."
      exit 1
    fi
  fi
fi

# Remove potentially existing extracted output first so the extractor scripts
# always write into a clean target directory. Only the directories and files we
# know the extractor produces are removed so unrelated files (such as
# `.gitkeep`) stay untouched. `Cameras` is included here because the extractor
# re-creates it on every run, but it is preserved after extraction (see below)
# since `mangosd` reads the camera M2 files at runtime.
rm -rf \
  "$extracted_data_dir/Buildings" \
  "$extracted_data_dir/Cameras" \
  "$extracted_data_dir/dbc" \
  "$extracted_data_dir/maps" \
  "$extracted_data_dir/mmaps" \
  "$extracted_data_dir/vmaps"
rm -f \
  "$extracted_data_dir/MaNGOSExtractor.log" \
  "$extracted_data_dir/MaNGOSExtractor_detailed.log"

cd "$tools_dir"
./ExtractResources.sh a "$client_data_dir" "$extracted_data_dir"

# `Buildings` is only consumed by `vmap_assembler` during extraction and is not
# used at runtime. The extractor logs are progress artifacts that can be
# regenerated on the next run.
rm -rf "$extracted_data_dir/Buildings"
rm -f \
  "$extracted_data_dir/MaNGOSExtractor.log" \
  "$extracted_data_dir/MaNGOSExtractor_detailed.log"
