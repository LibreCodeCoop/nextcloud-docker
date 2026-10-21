#!/usr/bin/env bash
# Publish only scanned images; moving tags wait for every CI matrix job to pass.
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

fail() {
  echo "::error title=Container publication failed::$1" >&2
  exit 2
}
validate_image() {
  [[ $1 =~ ^[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._-]+)+$ ]] || fail "Invalid image name: $1"
}
validate_revision() {
  [[ $1 =~ ^[0-9a-f]{40}$ ]] || fail "Expected a full 40-digit Git SHA"
}
stage() {
  local image=$1 revision=$2 variant=$3 local_component tag arch
  validate_image "$image"
  validate_revision "$revision"
  if [[ $variant == web ]]; then
    local_component=web
  else
    [[ $variant =~ ^[2-9][0-9]-fpm$ ]] || fail "Invalid Nextcloud channel: $variant"
    local_component=app
  fi
  for arch in amd64 arm64; do
    tag="sha-${revision}-${variant}-${arch}"
    bash "$script_dir/push-architecture.sh" "$image" "scan/${local_component}:${arch}" "$tag"
  done
}
publish() {
  local image=$1 tag=$2 prefix=$3
  bash "$script_dir/publish-manifest.sh" "$image" "$tag" \
    "${image}:${prefix}-amd64" "${image}:${prefix}-arm64"
}
promote() {
  local app_image=$1 web_image=$2 revision=$3 manifest_file=$4
  local major release prefix latest_prefix
  validate_image "$app_image"
  validate_image "$web_image"
  validate_revision "$revision"

  # Independently enforce the reviewed schema and EOL policy before any pushes.
  bash "$script_dir/nextcloud-versions.sh" matrix --file "$manifest_file" > /dev/null
  while IFS=$'\t' read -r major release; do
    prefix="sha-${revision}-${major}-fpm"
    publish "$app_image" "${major}-fpm" "$prefix"
    publish "$app_image" "${release}-fpm" "$prefix"
    latest_prefix=$prefix
  done < <(jq -r '.versions[] | [.major, (.image | split(":")[1] | split("-fpm@")[0])] | @tsv' "$manifest_file")

  [[ -n ${latest_prefix:-} ]] || fail "No approved stable Nextcloud major"
  publish "$app_image" stable-fpm "$latest_prefix"
  publish "$app_image" latest "$latest_prefix"

  publish "$web_image" main "sha-${revision}-web"
  publish "$web_image" latest "sha-${revision}-web"
}

case ${1:-} in
  stage-app)
    (( $# == 4 )) || fail 'Usage: stage-app <image> <revision> <major-fpm>'
    stage "$2" "$3" "$4"
    ;;
  stage-web)
    (( $# == 3 )) || fail 'Usage: stage-web <image> <revision>'
    stage "$2" "$3" web
    ;;
  promote)
    (( $# == 5 )) || fail 'Usage: promote <app-image> <web-image> <revision> <approved-json>'
    promote "$2" "$3" "$4" "$5"
    ;;
  *) fail 'Expected stage-app, stage-web or promote' ;;
esac
