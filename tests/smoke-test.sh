#!/usr/bin/env bash
#
# Smoke test for the images built by this repository.
#
# Builds (unless the images are handed over) and boots the real stack:
# postgres + app + web, on a throwaway Docker network. It then asserts that
# Nextcloud actually installs, that `occ status` reports it, that the HTTP
# front-end answers on status.php, and that the traceability labels are present.
#
# A green build only proves an image compiles. This proves it boots.
#
# Usage:
#   tests/smoke-test.sh [options]
#
# Options:
#   --app-image IMAGE     use this app image instead of building one
#   --web-image IMAGE     use this web image instead of building one
#   --source CHANNEL      release (default) or daily
#   --major MAJOR         assert the reported Nextcloud major
#   --base TAG            upstream nextcloud tag used as the base image
#   --timeout SECONDS     install timeout (default: 300)
#   --keep                keep the containers and network after the run
#
# Environment:
#   DOCKER_BIN            docker binary (default: docker)

set -euo pipefail

DOCKER_BIN="${DOCKER_BIN:-docker}"

SOURCE=release
MAJOR=""
BASE="stable-fpm"
TIMEOUT=300
KEEP=0
APP_IMAGE=""
WEB_IMAGE=""

usage() {
  sed -n '3,25p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-image) APP_IMAGE="$2"; shift 2 ;;
    --web-image) WEB_IMAGE="$2"; shift 2 ;;
    --source)    SOURCE="$2";    shift 2 ;;
    --major)     MAJOR="$2";     shift 2 ;;
    --base)      BASE="$2";      shift 2 ;;
    --timeout)   TIMEOUT="$2";   shift 2 ;;
    --keep)      KEEP=1;         shift ;;
    -h|--help)   usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
  printf 'Docker is required to run the smoke test.\n' >&2
  exit 127
fi

if [[ "$SOURCE" != "release" && "$SOURCE" != "daily" ]]; then
  printf 'Unsupported --source %s (expected release or daily)\n' "$SOURCE" >&2
  exit 2
fi

# Unique prefix so parallel runs on the same host never collide.
run_id="ncsmoke$$"
network="${run_id}-net"
db_name="${run_id}-db"
app_name="${run_id}-app"
web_name="${run_id}-web"
volume_name="${run_id}-html"
includes_volume="${run_id}-nginx-includes"

log() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mFAIL: %s\033[0m\n' "$*" >&2; diagnostics; exit 1; }

diagnostics() {
  printf '\n\033[1;33m--- diagnostics ---\033[0m\n' >&2
  for name in "$db_name" "$app_name" "$web_name"; do
    if "$DOCKER_BIN" inspect "$name" >/dev/null 2>&1; then
      printf '\n### %s\n' "$name" >&2
      "$DOCKER_BIN" logs --tail 40 "$name" >&2 || true
    fi
  done
}

cleanup() {
  status=$?
  if [[ "$KEEP" -eq 1 ]]; then
    printf '\nKeeping: %s %s %s %s %s %s\n' "$db_name" "$app_name" "$web_name" "$volume_name" "$includes_volume" "$network"
    return
  fi
  "$DOCKER_BIN" rm -f "$web_name" "$app_name" "$db_name" >/dev/null 2>&1 || true
  "$DOCKER_BIN" volume rm "$volume_name" "$includes_volume" >/dev/null 2>&1 || true
  "$DOCKER_BIN" network rm "$network" >/dev/null 2>&1 || true
  exit "$status"
}
trap cleanup EXIT

# --- build -------------------------------------------------------------------
if [[ -z "$APP_IMAGE" ]]; then
  log "Building app image (${SOURCE}, base ${BASE})"
  APP_IMAGE="${run_id}-app-image"
  build_args=(--build-arg "NEXTCLOUD_VERSION=${BASE}" --build-arg "NEXTCLOUD_SOURCE=${SOURCE}")
  if [[ -n "$MAJOR" ]]; then
    build_args+=(--build-arg "NEXTCLOUD_MAJOR=${MAJOR}")
  fi
  "$DOCKER_BIN" build "${build_args[@]}" --tag "$APP_IMAGE" .docker/app
fi

if [[ -z "$WEB_IMAGE" ]]; then
  log "Building web image"
  WEB_IMAGE="${run_id}-web-image"
  "$DOCKER_BIN" build --tag "$WEB_IMAGE" .docker/web
fi

# --- start the stack ---------------------------------------------------------
log "Starting postgres, app and web"

"$DOCKER_BIN" network create "$network" >/dev/null

"$DOCKER_BIN" volume create "$volume_name" >/dev/null

"$DOCKER_BIN" run -d --name "$db_name" --network "$network" --network-alias db \
  -e POSTGRES_DB=nextcloud \
  -e POSTGRES_USER=nextcloud \
  -e POSTGRES_PASSWORD=nextcloud \
  -e PGDATA=/var/lib/postgresql/data/pgdata \
  postgres:16-alpine >/dev/null

log "Waiting for postgres"
db_deadline=$((SECONDS + 60))
until "$DOCKER_BIN" exec "$db_name" pg_isready -U nextcloud -d nextcloud >/dev/null 2>&1; do
  if (( SECONDS >= db_deadline )); then fail "postgres did not become ready"; fi
  sleep 2
done

# The app container is reached by the web image through the "app" hostname, so
# the network alias below is part of the contract, not a convenience.
"$DOCKER_BIN" run -d --name "$app_name" --network "$network" --network-alias app \
  -v "${volume_name}:/var/www/html" \
  -e POSTGRES_DB=nextcloud \
  -e POSTGRES_USER=nextcloud \
  -e POSTGRES_PASSWORD=nextcloud \
  -e POSTGRES_HOST=db \
  -e NEXTCLOUD_ADMIN_USER=admin \
  -e NEXTCLOUD_ADMIN_PASSWORD=admin-admin-admin \
  -e NEXTCLOUD_TRUSTED_DOMAINS=localhost \
  -e NEXTCLOUD_ADMIN_EMAIL=admin@example.com \
  "$APP_IMAGE" >/dev/null

"$DOCKER_BIN" run -d --name "$web_name" --network "$network" \
  -v "${volume_name}:/var/www/html:ro" \
  -v "${includes_volume}:/etc/nginx/conf.d/includes" \
  "$WEB_IMAGE" >/dev/null

# --- wait for the install ----------------------------------------------------
log "Waiting for Nextcloud to install (timeout ${TIMEOUT}s)"
deadline=$((SECONDS + TIMEOUT))
occ_json=""
while true; do
  if occ_json=$("$DOCKER_BIN" exec --user www-data "$app_name" php occ status --output=json 2>/dev/null); then
    if grep -q '"installed":true' <<<"$occ_json"; then
      break
    fi
  fi
  if (( SECONDS >= deadline )); then
    fail "Nextcloud did not report installed within ${TIMEOUT}s (last: ${occ_json:-<none>})"
  fi
  sleep 5
done

log "occ status"
printf '%s\n' "$occ_json"

# --- assertions --------------------------------------------------------------
grep -q '"installed":true' <<<"$occ_json" || fail "occ status does not report installed"

version=$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' <<<"$occ_json" | head -n 1)
[[ -n "$version" ]] || fail "occ status did not report a version"
printf 'Nextcloud version: %s\n' "$version"

if [[ -n "$MAJOR" ]]; then
  reported_major="${version%%.*}"
  [[ "$reported_major" == "$MAJOR" ]] \
    || fail "expected Nextcloud major ${MAJOR}, image reports ${reported_major}"
  printf 'Nextcloud major %s matches the requested major\n' "$MAJOR"
fi

log "Checking the HTTP front-end"
status_json=""
http_deadline=$((SECONDS + 60))
while true; do
  if status_json=$("$DOCKER_BIN" exec "$web_name" wget -qO- http://localhost/status.php 2>/dev/null); then
    break
  fi
  if (( SECONDS >= http_deadline )); then fail "web container did not answer on status.php"; fi
  sleep 3
done
printf '%s\n' "$status_json"
grep -q '"installed":true' <<<"$status_json" || fail "status.php does not report installed"
grep -q '"version":"' <<<"$status_json" || fail "status.php does not report a version"

log "Checking traceability labels"
labels=$("$DOCKER_BIN" inspect --format '{{ json .Config.Labels }}' "$APP_IMAGE")
printf '%s\n' "$labels"
for label in \
  org.opencontainers.image.source \
  org.opencontainers.image.revision \
  org.opencontainers.image.created \
  org.opencontainers.image.version
do
  grep -q "\"${label}\":" <<<"$labels" || fail "missing label ${label}"
done

log "Smoke test passed"
printf 'image=%s version=%s source=%s\n' "$APP_IMAGE" "$version" "$SOURCE"
