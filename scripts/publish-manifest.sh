#!/usr/bin/env bash
# Common multi-platform manifest publisher for master and stable channels.
set -euo pipefail

image=${1:?Usage: publish-manifest.sh <image> <tag> <amd64-image> <arm64-image>}
tag=${2:?Missing target tag}
amd64=${3:?Missing amd64 staging image}
arm64=${4:?Missing arm64 staging image}
(( $# == 4 )) || { echo 'Expected exactly two architecture sources' >&2; exit 2; }

docker buildx imagetools create --tag "${image}:${tag}" "$amd64" "$arm64"
docker buildx imagetools inspect "${image}:${tag}"
