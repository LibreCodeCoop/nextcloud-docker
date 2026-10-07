#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s IMAGE\n' "$0" >&2
  exit 2
fi

image=$1
postgres_image=${NEXTCLOUD_IMAGE_TEST_POSTGRES_IMAGE:-postgres:18-alpine}
timeout_seconds=${NEXTCLOUD_IMAGE_TEST_TIMEOUT:-300}
runtime_user=${NEXTCLOUD_IMAGE_TEST_RUNTIME_USER:-www-data}

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is required to run the app image acceptance test.\n' >&2
  exit 127
fi

if ! docker image inspect "$image" >/dev/null 2>&1; then
  printf 'Image not found locally: %s\n' "$image" >&2
  exit 2
fi

image_arch=$(docker image inspect --format '{{.Architecture}}' "$image")
case "$image_arch" in
  amd64|arm64)
    image_platform="linux/$image_arch"
    ;;
  *)
    printf 'Unsupported image architecture: %s\n' "$image_arch" >&2
    exit 2
    ;;
esac

token="nextcloud-app-test-$$-${RANDOM}"
network_name="$token"
db_container="${token}-db"
app_container="${token}-app"
fcgi_client_image="${token}-fcgi-client"

network_created=false
db_created=false
app_created=false
fcgi_client_created=false

db_user=nextcloud
db_database=nextcloud
db_password="test-${RANDOM}-${RANDOM}-password"
admin_user=test_admin
admin_password="test-${RANDOM}-${RANDOM}-admin-password"

diagnostics() {
  printf '\n=== app container logs ===\n' >&2
  if $app_created; then
    docker logs "$app_container" >&2 || true
  else
    printf 'app container was not created\n' >&2
  fi

  printf '\n=== postgres container logs ===\n' >&2
  if $db_created; then
    docker logs "$db_container" >&2 || true
  else
    printf 'postgres container was not created\n' >&2
  fi
}

cleanup() {
  local status=$?
  set +e

  if [ "$status" -ne 0 ]; then
    diagnostics
  fi

  if $app_created; then
    docker rm -f "$app_container" >/dev/null 2>&1 || true
  fi
  if $db_created; then
    docker rm -f "$db_container" >/dev/null 2>&1 || true
  fi
  if $network_created; then
    docker network rm "$network_name" >/dev/null 2>&1 || true
  fi
  if $fcgi_client_created; then
    docker image rm -f "$fcgi_client_image" >/dev/null 2>&1 || true
  fi

  exit "$status"
}
trap cleanup EXIT

wait_until() {
  local description=$1
  shift

  local started now
  started=$(date +%s)

  while true; do
    if "$@"; then
      return 0
    fi

    now=$(date +%s)
    if [ $((now - started)) -ge "$timeout_seconds" ]; then
      printf 'Timed out after %ss waiting for %s.\n' "$timeout_seconds" "$description" >&2
      return 1
    fi

    sleep 2
  done
}

postgres_ready() {
  docker exec "$db_container" pg_isready -U "$db_user" -d "$db_database" >/dev/null 2>&1
}

nextcloud_installed() {
  local status
  status=$(docker exec -u "$runtime_user" "$app_container" php occ status --output=json 2>/dev/null) || return 1
  grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' <<<"$status"
}

printf 'Testing %s (%s)\n' "$image" "$image_platform"

docker network create "$network_name" >/dev/null
network_created=true

docker run -d \
  --name "$db_container" \
  --network "$network_name" \
  --network-alias db \
  -e "POSTGRES_USER=$db_user" \
  -e "POSTGRES_PASSWORD=$db_password" \
  -e "POSTGRES_DB=$db_database" \
  "$postgres_image" >/dev/null
db_created=true

wait_until 'PostgreSQL readiness' postgres_ready

docker run -d \
  --name "$app_container" \
  --network "$network_name" \
  --network-alias app \
  --platform "$image_platform" \
  -e POSTGRES_HOST=db \
  -e "POSTGRES_USER=$db_user" \
  -e "POSTGRES_PASSWORD=$db_password" \
  -e "POSTGRES_DB=$db_database" \
  -e "NEXTCLOUD_ADMIN_USER=$admin_user" \
  -e "NEXTCLOUD_ADMIN_PASSWORD=$admin_password" \
  -e NEXTCLOUD_TRUSTED_DOMAINS=localhost \
  "$image" >/dev/null
app_created=true

wait_until 'Nextcloud installation' nextcloud_installed

printf 'Nextcloud installed successfully.\n'
docker exec -u "$runtime_user" "$app_container" php occ status --output=json
docker exec -u "$runtime_user" "$app_container" php occ check

docker build -q -t "$fcgi_client_image" - <<'EOF' >/dev/null
FROM debian:trixie-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends libfcgi-bin \
    && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["cgi-fcgi"]
EOF
fcgi_client_created=true

fcgi_response=$(
  docker run --rm -i \
    --network "$network_name" \
    -e REQUEST_METHOD=GET \
    -e SCRIPT_NAME=/status.php \
    -e SCRIPT_FILENAME=/var/www/html/status.php \
    "$fcgi_client_image" \
    -bind -connect app:9000
)

if ! grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' <<<"$fcgi_response"; then
  printf 'FPM responded, but status.php did not report an installed instance.\n' >&2
  printf '%s\n' "$fcgi_response" >&2
  exit 1
fi

printf 'FPM accepted a FastCGI request and returned installed Nextcloud status.\n'
