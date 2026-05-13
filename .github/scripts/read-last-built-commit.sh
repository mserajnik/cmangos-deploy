#!/usr/bin/env bash

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

# Resolves the previous database image's commit hash for one source slot of a
# given package. The combined revision tag on the most recent image is parsed
# for the source's short SHA, then resolved to a full SHA via
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
package_endpoint="$(package_versions_endpoint "$PACKAGE_OWNER" "$PACKAGE_NAME")"

set +e
all_tags="$(gh api --paginate "$package_endpoint?per_page=100" \
  --jq '.[].metadata.container.tags[]?' 2>&1)"
gh_status=$?
set -e

if [[ $gh_status -ne 0 ]]; then
  if grep -Fq "HTTP 404" <<<"$all_tags"; then
    all_tags=""
  else
    printf '%s\n' "$all_tags" >&2
    fail "Failed to query package versions for '$PACKAGE_OWNER/$PACKAGE_NAME'."
  fi
fi

# Match the first combined-revision tag we see (the package list is sorted
# newest-first) and extract the short SHA for this source. The regex tolerates
# the three fragments appearing in any order.
short_sha=""
combined_tag_regex='^[a-z]+-(core|db|playerbots)\.[0-9a-f]{12}-(core|db|playerbots)\.[0-9a-f]{12}-(core|db|playerbots)\.[0-9a-f]{12}$'
fragment_regex="(^|-)${tag_fragment}\.([0-9a-f]{12})(-|$)"

while IFS= read -r tag; do
  [[ -z "$tag" ]] && continue

  if [[ "$tag" =~ $combined_tag_regex ]] && [[ "$tag" =~ $fragment_regex ]]; then
    short_sha="${BASH_REMATCH[2]}"
    break
  fi
done <<<"$all_tags"

if [[ -z "$short_sha" ]]; then
  echo "[$SOURCE] No prior package version with a parseable combined revision tag found; falling back to migration edit cutoff." >&2
  write_output commit_hash "$CUTOFF_COMMIT_HASH"
  exit 0
fi

repo="$SOURCE_REPOSITORY_OWNER/$SOURCE_REPOSITORY_NAME"
full_sha="$(gh api "repos/$repo/commits/$short_sha" --jq '.sha')"

if [[ -z "$full_sha" ]] || ! [[ "$full_sha" =~ ^[0-9a-f]{40}$ ]]; then
  fail "Failed to resolve short SHA '$short_sha' to a full SHA in '$repo'."
fi

write_output commit_hash "$full_sha"
