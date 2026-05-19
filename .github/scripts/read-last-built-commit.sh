#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Resolves the previous database image's commit hash for one source slot of a
# given package. The combined revision tag on the most recent image is parsed
# for the source's short commit hash, then resolved to a full commit hash via
# `gh api commits/<short>`. Falls back to a hard-coded cutoff anchor when no
# prior image exists (e.g., on a fork's first build).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env GH_TOKEN
require_env PACKAGE_OWNER
require_env PACKAGE_NAME
require_env SOURCE
require_env SOURCE_REPOSITORY_OWNER
require_env SOURCE_REPOSITORY_NAME
require_env CUTOFF_COMMIT_HASH

case "$SOURCE" in
core | database | playerbots) ;;
*)
  fail "Unsupported source '$SOURCE'. Expected one of: core, database, playerbots."
  ;;
esac

# Maps the migration edit source name to the fragment used in the combined
# revision tag built by `prepare-default-build.sh`. The tag shape is
# `<expansion>-core.<short>-db.<short>-playerbots.<short>`.
case "$SOURCE" in
core) tag_fragment="core" ;;
database) tag_fragment="db" ;;
playerbots) tag_fragment="playerbots" ;;
esac

# shellcheck disable=SC2153
all_tags="$(existing_tags_for_package "$PACKAGE_OWNER" "$PACKAGE_NAME")"

# Match the first combined-revision tag we see (the package list is sorted
# newest-first) and extract the short commit hash for this source. The regex
# tolerates the three fragments appearing in any order.
short_commit_hash=""
combined_tag_regex='^[a-z]+-(core|db|playerbots)\.[0-9a-f]{12}-(core|db|playerbots)\.[0-9a-f]{12}-(core|db|playerbots)\.[0-9a-f]{12}$'
fragment_regex="(^|-)${tag_fragment}\.([0-9a-f]{12})(-|$)"

while IFS= read -r tag; do
  [[ -z "$tag" ]] && continue

  if [[ "$tag" =~ $combined_tag_regex ]] && [[ "$tag" =~ $fragment_regex ]]; then
    short_commit_hash="${BASH_REMATCH[2]}"
    break
  fi
done <<<"$all_tags"

if [[ -z "$short_commit_hash" ]]; then
  echo "[$SOURCE] No prior package version with a parseable combined revision tag found; falling back to migration edit cutoff." >&2
  write_output commit_hash "$CUTOFF_COMMIT_HASH"
  exit 0
fi

full_commit_hash="$(resolve_commit_hash \
  "$SOURCE_REPOSITORY_OWNER" "$SOURCE_REPOSITORY_NAME" "$short_commit_hash")"

write_output commit_hash "$full_commit_hash"
