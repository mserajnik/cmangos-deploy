#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Michael Serajnik <https://github.com/mserajnik>
# SPDX-License-Identifier: AGPL-3.0-or-later

# Produces the per build metadata consumed by the reusable build workflow:
# Dockerfile path, target architectures, image tags, build arguments, OCI
# annotations, and labels for the requested workflow mode and image kind.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/helpers.sh"

require_env WORKFLOW_MODE
require_env IMAGE_KIND
require_env ARCHITECTURES
require_env EXPANSION
require_env REPOSITORY_OWNER
require_env CORE_REPOSITORY_URL
require_env DATABASE_REPOSITORY_URL
require_env PLAYERBOTS_REPOSITORY_URL
require_env OCI_ANNOTATION_AUTHORS
require_env OCI_ANNOTATION_URL
require_env OCI_ANNOTATION_DOCUMENTATION
require_env OCI_ANNOTATION_SOURCE
require_env OCI_ANNOTATION_VENDOR
require_env OCI_ANNOTATION_LICENSES

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# shellcheck disable=SC2153
architectures="$(trim "$ARCHITECTURES")"
# shellcheck disable=SC2153
expansion="$(trim "$EXPANSION")"
# shellcheck disable=SC2153
core_repository_url="$(trim "$CORE_REPOSITORY_URL")"
# shellcheck disable=SC2153
database_repository_url="$(trim "$DATABASE_REPOSITORY_URL")"
# shellcheck disable=SC2153
playerbots_repository_url="$(trim "$PLAYERBOTS_REPOSITORY_URL")"
# shellcheck disable=SC2153
oci_annotation_authors="$(trim "$OCI_ANNOTATION_AUTHORS")"
# shellcheck disable=SC2153
oci_annotation_vendor="$(trim "$OCI_ANNOTATION_VENDOR")"
patches_repository_url="$(trim "${CMANGOS_PATCHES_REPOSITORY_URL:-}")"

declare -a tags=()
declare -a mode_metadata_entries=()
declare -a label_only_entries=()
declare -a metadata_entries=()
declare -a label_lines=()
declare -a manifest_annotation_lines=()
declare -a index_annotation_lines=()
declare -a build_args=()

build_amd64="false"
build_arm64="false"
is_multi_arch="false"
title=""
description=""
base_name=""
ref_name=""
image_name_base=""
image_name=""
image=""
dockerfile=""
core_revision=""
database_revision=""
playerbots_revision=""

normalize_revision() {
  local revision

  revision="$(trim "$1")"

  if [[ "$revision" =~ ^[0-9a-fA-F]{12,}$ ]]; then
    revision="$(short_revision "$revision")"
  fi

  sanitize_docker_tag_fragment "$revision"
}

case "$architectures" in
both | "Both amd64 and arm64")
  build_amd64="true"
  build_arm64="true"
  is_multi_arch="true"
  ;;
amd64 | "amd64 only")
  build_amd64="true"
  ;;
arm64 | "arm64 only")
  build_arm64="true"
  ;;
*)
  fail "Unsupported architectures value '$architectures'."
  ;;
esac

case "$IMAGE_KIND" in
server)
  require_env OCI_ANNOTATION_SERVER_TITLE
  require_env OCI_ANNOTATION_SERVER_DESCRIPTION
  require_env OCI_ANNOTATION_SERVER_BASE_NAME

  image_name_base="cmangos-server"
  dockerfile="./docker/server/Dockerfile"
  title="$(trim "$OCI_ANNOTATION_SERVER_TITLE")"
  description="$(trim "$OCI_ANNOTATION_SERVER_DESCRIPTION")"
  base_name="$(trim "$OCI_ANNOTATION_SERVER_BASE_NAME")"
  ;;
database)
  require_env OCI_ANNOTATION_DATABASE_TITLE
  require_env OCI_ANNOTATION_DATABASE_DESCRIPTION
  require_env OCI_ANNOTATION_DATABASE_BASE_NAME

  image_name_base="cmangos-database"
  dockerfile="./docker/database/Dockerfile"
  title="$(trim "$OCI_ANNOTATION_DATABASE_TITLE")"
  description="$(trim "$OCI_ANNOTATION_DATABASE_DESCRIPTION")"
  base_name="$(trim "$OCI_ANNOTATION_DATABASE_BASE_NAME")"
  ;;
*)
  fail "Unsupported image kind '$IMAGE_KIND'."
  ;;
esac

case "$expansion" in
classic | tbc | wotlk) ;;
*) fail "Unsupported expansion '$expansion'." ;;
esac

require_env REGISTRY

case "$WORKFLOW_MODE" in
default)
  require_env CORE_COMMIT_HASH
  require_env DATABASE_COMMIT_HASH
  require_env PLAYERBOTS_COMMIT_HASH
  require_env COMBINED_REVISION_TAG

  core_revision="$(trim "$CORE_COMMIT_HASH")"
  database_revision="$(trim "$DATABASE_COMMIT_HASH")"
  playerbots_revision="$(trim "$PLAYERBOTS_COMMIT_HASH")"
  primary_tag="$(trim "$COMBINED_REVISION_TAG")"

  image_name="$REPOSITORY_OWNER/$image_name_base-$expansion"
  image="$REGISTRY/$image_name"
  ref_name="$image:$primary_tag"

  tags+=("$image:latest")
  tags+=("$ref_name")

  mode_metadata_entries+=(
    "version=$primary_tag"
    "revision=$core_revision"
  )
  ;;
custom)
  require_env CORE_REVISION
  require_env DATABASE_REVISION
  require_env PLAYERBOTS_REVISION
  require_env CORE_REPOSITORY_OWNER
  require_env CORE_REPOSITORY_NAME

  # shellcheck disable=SC2153
  core_revision="$(trim "$CORE_REVISION")"
  # shellcheck disable=SC2153
  database_revision="$(trim "$DATABASE_REVISION")"
  # shellcheck disable=SC2153
  playerbots_revision="$(trim "$PLAYERBOTS_REVISION")"
  # shellcheck disable=SC2153
  core_repository_owner="$(trim "$CORE_REPOSITORY_OWNER")"
  # shellcheck disable=SC2153
  core_repository_name="$(trim "$CORE_REPOSITORY_NAME")"
  custom_tag_fragment="$(trim "${CUSTOM_TAG_FRAGMENT:-}")"

  image_name="$REPOSITORY_OWNER/$image_name_base-$expansion-custom"
  image="$REGISTRY/$image_name"

  if [[ -n "$custom_tag_fragment" ]]; then
    sanitized_custom_tag_fragment="$(sanitize_docker_tag_fragment "$custom_tag_fragment")"
    primary_tag="$expansion-$sanitized_custom_tag_fragment"
  else
    sanitized_core_owner="$(sanitize_docker_tag_fragment "$core_repository_owner")"
    sanitized_core_name="$(sanitize_docker_tag_fragment "$core_repository_name")"
    primary_tag="$expansion-$sanitized_core_owner-$sanitized_core_name"
    primary_tag+="-core.$(normalize_revision "$core_revision")"
    primary_tag+="-db.$(normalize_revision "$database_revision")"
    primary_tag+="-playerbots.$(normalize_revision "$playerbots_revision")"
  fi

  ref_name="$image:$primary_tag"
  tags+=("$ref_name")

  # Custom images do not define an OCI version, so clear the inherited base
  # image version label without adding a matching manifest/index annotation.
  label_only_entries+=("version=")
  mode_metadata_entries+=("revision=$core_revision")
  ;;
*)
  fail "Unsupported workflow mode '$WORKFLOW_MODE'."
  ;;
esac

build_args+=(
  "CMANGOS_EXPANSION=$expansion"
  "CMANGOS_CORE_REPOSITORY_URL=$core_repository_url"
  "CMANGOS_CORE_REVISION=$core_revision"
  "CMANGOS_PLAYERBOTS_REPOSITORY_URL=$playerbots_repository_url"
  "CMANGOS_PLAYERBOTS_REVISION=$playerbots_revision"
  "CMANGOS_PATCHES_REPOSITORY_URL=$patches_repository_url"
  "CMANGOS_FAIL_ON_PATCH_ERROR=1"
)

if [[ "$IMAGE_KIND" == "database" ]]; then
  build_args+=(
    "CMANGOS_DATABASE_REPOSITORY_URL=$database_repository_url"
    "CMANGOS_DATABASE_REVISION=$database_revision"
    "CMANGOS_MIGRATION_EDITS=${MIGRATION_EDITS:-}"
  )
fi

metadata_entries=(
  "created=$timestamp"
  "authors=$oci_annotation_authors"
  "url=$OCI_ANNOTATION_URL"
  "documentation=$OCI_ANNOTATION_DOCUMENTATION"
  "source=$OCI_ANNOTATION_SOURCE"
)

if ((${#mode_metadata_entries[@]} > 0)); then
  metadata_entries+=("${mode_metadata_entries[@]}")
fi

metadata_entries+=(
  "vendor=$oci_annotation_vendor"
  "licenses=$OCI_ANNOTATION_LICENSES"
  "ref.name=$ref_name"
  "title=$title"
  "description=$description"
  "base.name=$base_name"
)

for entry in "${metadata_entries[@]}"; do
  key="${entry%%=*}"
  value="${entry#*=}"

  label_lines+=("org.opencontainers.image.$key=$value")
  manifest_annotation_lines+=("manifest:org.opencontainers.image.$key=$value")

  if [[ "$is_multi_arch" == "true" ]]; then
    index_annotation_lines+=("index:org.opencontainers.image.$key=$value")
  fi
done

if ((${#label_only_entries[@]} > 0)); then
  for entry in "${label_only_entries[@]}"; do
    key="${entry%%=*}"
    value="${entry#*=}"

    label_lines+=("org.opencontainers.image.$key=$value")
  done
fi

extra_label_lines=(
  "io.github.mserajnik.cmangos-deploy.expansion=$expansion"
  "io.github.mserajnik.cmangos-deploy.core.repository=$core_repository_url"
  "io.github.mserajnik.cmangos-deploy.core.revision=$core_revision"
  "io.github.mserajnik.cmangos-deploy.database.repository=$database_repository_url"
  "io.github.mserajnik.cmangos-deploy.database.revision=$database_revision"
  "io.github.mserajnik.cmangos-deploy.playerbots.repository=$playerbots_repository_url"
  "io.github.mserajnik.cmangos-deploy.playerbots.revision=$playerbots_revision"
)

label_lines+=("${extra_label_lines[@]}")

printf -v tags_output '%s,' "${tags[@]}"
tags_output="${tags_output%,}"

printf -v manifest_annotations_output '%s\n' "${manifest_annotation_lines[@]}"
manifest_annotations_output="${manifest_annotations_output%$'\n'}"

if ((${#index_annotation_lines[@]} > 0)); then
  printf -v index_annotations_output '%s\n' "${index_annotation_lines[@]}"
  index_annotations_output="${index_annotations_output%$'\n'}"
else
  index_annotations_output=""
fi

printf -v labels_output '%s\n' "${label_lines[@]}"
labels_output="${labels_output%$'\n'}"

printf -v build_args_output '%s\n' "${build_args[@]}"
build_args_output="${build_args_output%$'\n'}"

write_output image "$image"
write_output package_name "${image_name##*/}"
write_output dockerfile "$dockerfile"
write_output build_amd64 "$build_amd64"
write_output build_arm64 "$build_arm64"
write_output is_multi_arch "$is_multi_arch"
write_output tags "$tags_output"
write_multiline_output build_args "$build_args_output"
write_multiline_output manifest_annotations "$manifest_annotations_output"
write_multiline_output index_annotations "$index_annotations_output"
write_multiline_output labels "$labels_output"
