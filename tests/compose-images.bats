#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
}

assert_published_images() {
  local file="$1" config
  config=$(NEXTCLOUD_VERSION=34-fpm docker compose \
    --project-directory "$REPO_ROOT" \
    -f "$REPO_ROOT/$file" config --format json 2>/dev/null) || return 1

  jq -e '
    .services.app.image == "ghcr.io/librecodecoop/nextcloud-docker-app:34-fpm" and
    .services.cron.image == "ghcr.io/librecodecoop/nextcloud-docker-app:34-fpm" and
    .services.web.image == "ghcr.io/librecodecoop/nextcloud-docker-web:main" and
    ([.services.app, .services.cron, .services.web] | all(has("build") | not))
  ' <<< "$config" >/dev/null
}

@test "standard Compose uses published images without local builds" {
  assert_published_images docker-compose.yml
}

@test "Garage S3 Compose uses published images without local builds" {
  assert_published_images docker-compose-garages3.yml
}
