#!/usr/bin/env bash
set -euo pipefail

app_image=${1:?Usage: publish-master-manifest.sh <app-image> <revision>}
revision=${2:?Missing revision}

bash "$(dirname "$0")/publish-manifest.sh" "$app_image" master-fpm \
  "${app_image}:master-fpm-${revision}-amd64" \
  "${app_image}:master-fpm-${revision}-arm64"
