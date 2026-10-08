#!/usr/bin/env bash

set -euo pipefail

app_image=${1:?Usage: push-master-architecture.sh <app-image> <source-tag> <revision> <arch>}
source_tag=${2:?Usage: push-master-architecture.sh <app-image> <source-tag> <revision> <arch>}
revision=${3:?Usage: push-master-architecture.sh <app-image> <source-tag> <revision> <arch>}
arch=${4:?Usage: push-master-architecture.sh <app-image> <source-tag> <revision> <arch>}

case "${arch}" in
  amd64|arm64) ;;
  *)
    echo "Unsupported architecture: ${arch}" >&2
    exit 2
    ;;
esac

staging_tag="master-fpm-${revision}-${arch}"
docker tag "${source_tag}" "${app_image}:${staging_tag}"
docker push "${app_image}:${staging_tag}"
