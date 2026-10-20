#!/usr/bin/env bash
# Reuse the same tested push sequence for release and development channels.
set -euo pipefail

image=${1:?Usage: push-architecture.sh <image> <source-image> <staging-tag>}
source_image=${2:?Missing source image}
staging_tag=${3:?Missing staging tag}
(( $# == 3 )) || exit 2

docker tag "$source_image" "${image}:${staging_tag}"
docker push "${image}:${staging_tag}"
