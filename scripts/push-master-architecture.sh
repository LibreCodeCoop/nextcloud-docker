#!/usr/bin/env bash
set -euo pipefail

app_image=${1:?Usage: push-master-architecture.sh <app-image> <source-tag> <revision> <arch>}
source_tag=${2:?Missing source image}
revision=${3:?Missing revision}
arch=${4:?Missing architecture}

case "$arch" in
  amd64|arm64) ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 2 ;;
esac

bash "$(dirname "$0")/push-architecture.sh" \
  "$app_image" "$source_tag" "master-fpm-${revision}-${arch}"
