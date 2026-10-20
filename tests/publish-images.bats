#!/usr/bin/env bats
# Docker is mocked; these tests never push real images to a registry.
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TEST_ROOT=$(mktemp -d)
  export TEST_ROOT
  mkdir -p "$TEST_ROOT/bin"
  export PATH="$TEST_ROOT/bin:$PATH"
  export DOCKER_COMMAND_LOG="$TEST_ROOT/docker.log"
  touch "$DOCKER_COMMAND_LOG"
  script=scripts/publish-images.sh
  APP_IMAGE=ghcr.io/librecodecoop/nextcloud-docker-app
  WEB_IMAGE=ghcr.io/librecodecoop/nextcloud-docker-web
  SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  INVENTORY="$TEST_ROOT/approved.json"
  jq '.versions |= map(.eol = "2099-12")' \
    .github/nextcloud-supported.json > "$INVENTORY"
  cat > "$TEST_ROOT/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$DOCKER_COMMAND_LOG"
MOCK
  chmod +x "$TEST_ROOT/bin/docker"
}
teardown() {
  rm -rf "$TEST_ROOT"
}
@test "stage-app only pushes its requested architecture images" {
  run bash "$script" stage-app "$APP_IMAGE" "$SHA" 34-fpm
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$DOCKER_COMMAND_LOG")" -eq 4 ]
  grep -Fx "tag scan/app:amd64 ${APP_IMAGE}:sha-${SHA}-34-fpm-amd64" "$DOCKER_COMMAND_LOG"
  grep -Fx "push ${APP_IMAGE}:sha-${SHA}-34-fpm-arm64" "$DOCKER_COMMAND_LOG"
}
@test "web staging never depends on a Nextcloud major" {
  run bash "$script" stage-web "$WEB_IMAGE" "$SHA"
  [ "$status" -eq 0 ]
  grep -Fx "tag scan/web:amd64 ${WEB_IMAGE}:sha-${SHA}-web-amd64" "$DOCKER_COMMAND_LOG"
  ! grep -q '35-fpm' "$DOCKER_COMMAND_LOG"
}
@test "invalid channel, image or SHA never invokes Docker" {
  run bash "$script" stage-app "$APP_IMAGE" "$SHA" '35;exit'
  [ "$status" -ne 0 ]
  run bash "$script" stage-app "$APP_IMAGE" invalid 35-fpm
  [ "$status" -ne 0 ]
  run bash "$script" stage-app 'bad;rm' "$SHA" 35-fpm
  [ "$status" -ne 0 ]
  [ ! -s "$DOCKER_COMMAND_LOG" ]
}
@test "publish all approved versions and newest aliases after validation" {
  run bash "$script" promote "$APP_IMAGE" "$WEB_IMAGE" "$SHA" "$INVENTORY"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^buildx imagetools create ' "$DOCKER_COMMAND_LOG")" -eq 10 ]
  grep -Fx "buildx imagetools create --tag ${APP_IMAGE}:33-fpm ${APP_IMAGE}:sha-${SHA}-33-fpm-amd64 ${APP_IMAGE}:sha-${SHA}-33-fpm-arm64" "$DOCKER_COMMAND_LOG"
  grep -Fx "buildx imagetools create --tag ${APP_IMAGE}:35.0.2-fpm ${APP_IMAGE}:sha-${SHA}-35-fpm-amd64 ${APP_IMAGE}:sha-${SHA}-35-fpm-arm64" "$DOCKER_COMMAND_LOG"
  grep -Fx "buildx imagetools create --tag ${APP_IMAGE}:latest ${APP_IMAGE}:sha-${SHA}-35-fpm-amd64 ${APP_IMAGE}:sha-${SHA}-35-fpm-arm64" "$DOCKER_COMMAND_LOG"
  grep -Fx "buildx imagetools create --tag ${WEB_IMAGE}:main ${WEB_IMAGE}:sha-${SHA}-web-amd64 ${WEB_IMAGE}:sha-${SHA}-web-arm64" "$DOCKER_COMMAND_LOG"
  grep -Fx "buildx imagetools create --tag ${WEB_IMAGE}:latest ${WEB_IMAGE}:sha-${SHA}-web-amd64 ${WEB_IMAGE}:sha-${SHA}-web-arm64" "$DOCKER_COMMAND_LOG"
}
@test "latest follows Nextcloud 36 when approved, without code changes" {
  jq '.versions = (.versions[1:] + [{"major":36,"release":"36.0.0","eol":"2099-12"}])' \
    "$INVENTORY" > "$TEST_ROOT/next.json"
  run bash "$script" promote "$APP_IMAGE" "$WEB_IMAGE" "$SHA" "$TEST_ROOT/next.json"
  [ "$status" -eq 0 ]
  grep -Fx "buildx imagetools create --tag ${APP_IMAGE}:latest ${APP_IMAGE}:sha-${SHA}-36-fpm-amd64 ${APP_IMAGE}:sha-${SHA}-36-fpm-arm64" "$DOCKER_COMMAND_LOG"
  ! grep -q "sha-${SHA}-33-fpm" "$DOCKER_COMMAND_LOG"
}
@test "expired inventory stops before any Docker operation" {
  jq '.versions[0].eol = "2026-09"' "$INVENTORY" > "$TEST_ROOT/expired.json"
  run bash "$script" promote "$APP_IMAGE" "$WEB_IMAGE" "$SHA" "$TEST_ROOT/expired.json"
  [ "$status" -ne 0 ]
  [ ! -s "$DOCKER_COMMAND_LOG" ]
}
@test "upstream master still uses same tested manifest publisher" {
  run bash scripts/publish-master-manifest.sh "$APP_IMAGE" "$SHA"
  [ "$status" -eq 0 ]
  grep -Fx "buildx imagetools create --tag ${APP_IMAGE}:master-fpm ${APP_IMAGE}:master-fpm-${SHA}-amd64 ${APP_IMAGE}:master-fpm-${SHA}-arm64" "$DOCKER_COMMAND_LOG"
}
