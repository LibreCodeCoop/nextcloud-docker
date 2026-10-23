#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
}

assert_published_images() {
  local file="$1" selected_tag="$2" expected_tag="$3" config

  # Compose config validates interpolation without pulling any registry image.
  # Empty selected_tag exercises the fallback even if a local .env exists.
  config=$(NEXTCLOUD_VERSION="$selected_tag" docker compose \
    --env-file /dev/null \
    --project-directory "$REPO_ROOT" \
    -f "$REPO_ROOT/$file" config --format json) || return 1

  jq -e --arg app_image "ghcr.io/librecodecoop/nextcloud-docker-app:$expected_tag" '
    .services.app.image == $app_image and
    .services.cron.image == $app_image and
    .services.web.image == "ghcr.io/librecodecoop/nextcloud-docker-web:main" and
    (.services.cron.entrypoint == ["/cron.sh"]) and
    ([.services.app, .services.cron, .services.web] | all(has("build") | not))
  ' <<< "$config" >/dev/null
}

@test "standard Compose defaults to the stable-fpm channel" {
  assert_published_images docker-compose.yml "" stable-fpm
}

@test "Garage S3 Compose defaults to the stable-fpm channel" {
  assert_published_images docker-compose-garages3.yml "" stable-fpm
}

@test "standard Compose applies an arbitrary image tag to both app and cron" {
  assert_published_images docker-compose.yml "test-version-fpm" "test-version-fpm"
}

@test "Garage S3 Compose applies an arbitrary image tag to both app and cron" {
  assert_published_images docker-compose-garages3.yml "test-version-fpm" "test-version-fpm"
}

@test "sample environment selects the moving stable-fpm channel" {
  run grep -Fx "NEXTCLOUD_VERSION=stable-fpm" "$REPO_ROOT/.env.example"
  [ "$status" -eq 0 ]
}
