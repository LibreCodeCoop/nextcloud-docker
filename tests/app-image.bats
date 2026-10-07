#!/usr/bin/env bats

setup() {
  : "${APP_IMAGE:?APP_IMAGE must reference an already-built local image}"

  command -v docker >/dev/null 2>&1 || {
    echo "Docker is required to run the app image acceptance test." >&2
    return 127
  }

  docker image inspect "$APP_IMAGE" >/dev/null 2>&1 || {
    echo "Image not found locally: $APP_IMAGE" >&2
    return 2
  }

  POSTGRES_IMAGE=${NEXTCLOUD_IMAGE_TEST_POSTGRES_IMAGE:-postgres:18-alpine}
  TIMEOUT_SECONDS=${NEXTCLOUD_IMAGE_TEST_TIMEOUT:-300}
  RUNTIME_USER=${NEXTCLOUD_IMAGE_TEST_RUNTIME_USER:-www-data}

  IMAGE_ARCH=$(docker image inspect --format '{{.Architecture}}' "$APP_IMAGE")
  case "$IMAGE_ARCH" in
    amd64|arm64) IMAGE_PLATFORM="linux/$IMAGE_ARCH" ;;
    *)
      echo "Unsupported image architecture: $IMAGE_ARCH" >&2
      return 2
      ;;
  esac

  TEST_ID="nextcloud-app-test-$$-${BATS_TEST_NUMBER}-${RANDOM}"
  NETWORK_NAME="$TEST_ID"
  DB_CONTAINER="${TEST_ID}-db"
  APP_CONTAINER="${TEST_ID}-app"
  FCGI_CLIENT_IMAGE="nextcloud-app-test-fcgi-client"

  DB_USER=nextcloud
  DB_DATABASE=nextcloud
  DB_PASSWORD="test-${RANDOM}-${RANDOM}-password"
  ADMIN_USER=test_admin
  ADMIN_PASSWORD="test-${RANDOM}-${RANDOM}-admin-password"

  NETWORK_CREATED=false
  DB_CREATED=false
  APP_CREATED=false
}

teardown() {
  if $APP_CREATED; then
    docker rm -f "$APP_CONTAINER" >/dev/null 2>&1 || true
  fi
  if $DB_CREATED; then
    docker rm -f "$DB_CONTAINER" >/dev/null 2>&1 || true
  fi
  if $NETWORK_CREATED; then
    docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
  fi
}

diagnostics() {
  echo
  echo "=== app container logs ===" >&2
  if $APP_CREATED; then
    docker logs "$APP_CONTAINER" >&2 || true
  else
    echo "app container was not created" >&2
  fi

  echo
  echo "=== postgres container logs ===" >&2
  if $DB_CREATED; then
    docker logs "$DB_CONTAINER" >&2 || true
  else
    echo "postgres container was not created" >&2
  fi
}

fail_with_diagnostics() {
  local message=$1
  diagnostics
  echo "$message" >&2
  return 1
}

wait_until() {
  local description=$1
  shift

  local started now
  started=$(date +%s)

  while ! "$@"; do
    now=$(date +%s)
    if [ $((now - started)) -ge "$TIMEOUT_SECONDS" ]; then
      fail_with_diagnostics "Timed out after ${TIMEOUT_SECONDS}s waiting for $description."
      return 1
    fi
    sleep 2
  done
}

postgres_ready() {
  docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_DATABASE" >/dev/null 2>&1
}

nextcloud_installed() {
  local status
  status=$(docker exec -u "$RUNTIME_USER" "$APP_CONTAINER" php occ status --output=json 2>/dev/null) || return 1
  grep -Eq '"installed"[[:space:]]*:[[:space:]]*true' <<<"$status"
}

ensure_fcgi_client() {
  if docker image inspect "$FCGI_CLIENT_IMAGE" >/dev/null 2>&1; then
    return
  fi

  docker build -q -t "$FCGI_CLIENT_IMAGE" - <<'EOF' >/dev/null
FROM debian:trixie-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends libfcgi-bin \
    && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["cgi-fcgi"]
EOF
}

@test "app image installs Nextcloud and serves it through FPM" {
  echo "Testing $APP_IMAGE ($IMAGE_PLATFORM)"

  run docker network create "$NETWORK_NAME"
  [ "$status" -eq 0 ]
  NETWORK_CREATED=true

  run docker run -d \
    --name "$DB_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias db \
    -e "POSTGRES_USER=$DB_USER" \
    -e "POSTGRES_PASSWORD=$DB_PASSWORD" \
    -e "POSTGRES_DB=$DB_DATABASE" \
    "$POSTGRES_IMAGE"
  [ "$status" -eq 0 ]
  DB_CREATED=true

  wait_until "PostgreSQL readiness" postgres_ready

  run docker run -d \
    --name "$APP_CONTAINER" \
    --network "$NETWORK_NAME" \
    --network-alias app \
    --platform "$IMAGE_PLATFORM" \
    -e POSTGRES_HOST=db \
    -e "POSTGRES_USER=$DB_USER" \
    -e "POSTGRES_PASSWORD=$DB_PASSWORD" \
    -e "POSTGRES_DB=$DB_DATABASE" \
    -e "NEXTCLOUD_ADMIN_USER=$ADMIN_USER" \
    -e "NEXTCLOUD_ADMIN_PASSWORD=$ADMIN_PASSWORD" \
    -e NEXTCLOUD_TRUSTED_DOMAINS=localhost \
    "$APP_IMAGE"
  [ "$status" -eq 0 ]
  APP_CREATED=true

  wait_until "Nextcloud installation" nextcloud_installed

  run docker exec -u "$RUNTIME_USER" "$APP_CONTAINER" php occ status --output=json
  [ "$status" -eq 0 ]
  [[ "$output" =~ "installed"[[:space:]]*:[[:space:]]*true ]]

  run docker exec -u "$RUNTIME_USER" "$APP_CONTAINER" php occ check
  if [ "$status" -ne 0 ]; then
    fail_with_diagnostics "occ check failed."
  fi

  ensure_fcgi_client

  run docker run --rm -i \
    --network "$NETWORK_NAME" \
    -e REQUEST_METHOD=GET \
    -e SCRIPT_NAME=/status.php \
    -e SCRIPT_FILENAME=/var/www/html/status.php \
    "$FCGI_CLIENT_IMAGE" \
    -bind -connect app:9000

  if [ "$status" -ne 0 ]; then
    fail_with_diagnostics "FPM did not accept the FastCGI request."
  fi
  [[ "$output" =~ "installed"[[:space:]]*:[[:space:]]*true ]]
}
