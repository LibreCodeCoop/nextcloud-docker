#!/usr/bin/env bash
# Emit true only when a published image is missing or its upstream base changed.
set -euo pipefail

app_image=${1:?Usage: needs-rebuild.sh <app-image> <web-image> <git-sha>}
web_image=${2:?Missing web image}
revision=${3:?Missing Git revision}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

[[ $revision =~ ^[a-f0-9]{40}$ ]] || exit 2

matches_published() {
  local base=$1 target=$2 upstream metadata
  upstream=$(docker buildx imagetools inspect "$base" --format '{{.Manifest.Digest}}') || exit 2
  [[ $upstream =~ ^sha256:[a-f0-9]{64}$ ]] || exit 2

  # Old images without provenance are rebuilt once. Both architectures must match.
  metadata=$(docker buildx imagetools inspect "$target" --format '{{json .Image}}' 2>/dev/null) || return 1
  jq -e --arg digest "$upstream" --arg revision "$revision" '
    . as $images |
    all(["linux/amd64", "linux/arm64"][];
      $images[.].config.Labels["org.opencontainers.image.base.digest"] == $digest and
      $images[.].config.Labels["org.opencontainers.image.revision"] == $revision)
  ' <<< "$metadata" > /dev/null
}

while IFS=$'\t' read -r major release; do
  if ! matches_published "nextcloud:${release}-fpm" "${app_image}:${major}-fpm"; then
    echo true
    exit 0
  fi
done < <(jq -r '.versions[] | [.major, .release] | @tsv' "$root/.github/nextcloud-supported.json")

if ! matches_published nginx:alpine "${web_image}:main"; then
  echo true
  exit 0
fi

echo false
