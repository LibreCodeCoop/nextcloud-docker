#!/usr/bin/env bash

set -euo pipefail

base_tag=${1:?Usage: resolve-nextcloud-upstream.sh <base-tag> <daily-url>}
daily_url=${2:?Usage: resolve-nextcloud-upstream.sh <base-tag> <daily-url>}

token_response="$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/nextcloud:pull")"
token="$(printf '%s' "${token_response}" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ -z "${token}" ]; then
  echo "Could not obtain Docker Hub token" >&2
  exit 1
fi

headers="$(mktemp)"
checksum_file="$(mktemp)"
trap 'rm -f "$headers" "$checksum_file"' EXIT

curl -fsSLI \
  -H "Authorization: Bearer ${token}" \
  -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
  -D "${headers}" \
  -o /dev/null \
  "https://registry-1.docker.io/v2/library/nextcloud/manifests/${base_tag}"

base_digest="$(awk 'BEGIN { IGNORECASE=1 } /^docker-content-digest:/ { gsub("\r", "", $2); print $2; exit }' "${headers}")"
if [[ ! "${base_digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "Could not resolve nextcloud:${base_tag} digest" >&2
  exit 1
fi

archive_name="$(basename "${daily_url}")"
curl -fsSL "${daily_url}.sha512" -o "${checksum_file}"
source_sha512="$(awk -v archive="${archive_name}" '$2 == archive { print $1; exit }' "${checksum_file}")"
if [[ ! "${source_sha512}" =~ ^[0-9a-fA-F]{128}$ ]]; then
  echo "Could not resolve SHA-512 for ${archive_name}" >&2
  exit 1
fi

printf 'base_image=nextcloud@%s\n' "${base_digest}"
printf 'base_digest=%s\n' "${base_digest}"
printf 'source_sha512=%s\n' "${source_sha512,,}"
printf 'created=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
