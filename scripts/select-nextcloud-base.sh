#!/usr/bin/env bash
set -euo pipefail

tag=${1:?Usage: select-nextcloud-base.sh <Nextcloud-release>-fpm}
[[ $tag =~ ^([0-9]{2,3})[.][0-9]+[.][0-9]+-fpm$ ]] || {
  echo "Invalid Nextcloud FPM release tag: $tag" >&2
  exit 2
}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
file="$root/.docker/nextcloud-bases/${BASH_REMATCH[1]}/Dockerfile"
[[ -f $file ]] || { echo "No pinned base for $tag" >&2; exit 1; }

base=$(awk 'NR == 1 && $1 == "FROM" && NF == 2 {print $2}' "$file")
digest="${base##*@sha256:}"
[[ $base == "nextcloud:$tag@sha256:$digest" && $digest =~ ^[a-f0-9]{64}$ ]] || {
  echo "Pinned base in $file does not match reviewed release $tag" >&2
  exit 1
}
printf '%s\n' "$base"
