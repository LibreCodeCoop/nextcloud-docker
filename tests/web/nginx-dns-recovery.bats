#!/usr/bin/env bats

setup() {
  : "${WEB_IMAGE:?Set WEB_IMAGE to the built Nextcloud web image}"
  FPM_IMAGE="${FPM_IMAGE:-php:8.4-fpm-alpine}"
  test_id="nc-fpm-dns-${BATS_TEST_NUMBER}-$$"
  network="$test_id"
  web="$test_id-web"
  app="$test_id-app"
  holder="$test_id-holder"
  workdir="$(mktemp -d)"

  mkdir -p "$workdir/htdocs" "$workdir/includes"
  chmod 755 "$workdir"
  printf '%s\n' "<?php echo 'healthy';" > "$workdir/htdocs/status.php"
  for file in composer.json composer.lock package.json package-lock.json core/shipped.json; do
    mkdir -p "$workdir/htdocs/$(dirname "$file")"
    printf '%s\n' '{"fixture":true}' > "$workdir/htdocs/$file"
  done

  # Docker only permits --ip on networks with a user-configured subnet.
  # Let Docker select an available subnet instead of hardcoding an address.
  allocator="$network-allocator"
  docker network create "$allocator" >/dev/null
  subnet="$(docker network inspect --format '{{(index .IPAM.Config 0).Subnet}}' "$allocator")"
  docker network rm "$allocator" >/dev/null
  docker network create --subnet "$subnet" "$network" >/dev/null
}

teardown() {
  docker rm -f "$web" "$app" "$holder" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  docker network rm "$allocator" >/dev/null 2>&1 || true
  if [[ -n "${workdir:-}" ]]; then
    rm -rf "$workdir"
  fi
}

start_app() {
  docker run -d --name "$app" --network "$network" --network-alias app \
    --volume "$workdir/htdocs:/var/www/html:ro" "$FPM_IMAGE" >/dev/null
}

wait_for_php() {
  local response attempt
  for ((attempt = 0; attempt < 30; attempt++)); do
    if response="$(docker exec "$web" wget -q -T 3 -O - http://127.0.0.1/status.php 2>/dev/null)" \
       && [[ "$response" == "healthy" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

assert_healthy() {
  if ! wait_for_php; then
    docker logs --tail 25 "$web" >&2
    echo "nginx did not recover its PHP-FPM connection" >&2
    return 1
  fi
}

@test "nginx reconnects to a recreated PHP-FPM at a different IP without reload" {
  start_app
  docker run -d --name "$web" --network "$network" \
    --volume "$workdir/htdocs:/var/www/html:ro" \
    --volume "$workdir/includes:/etc/nginx/conf.d/includes:ro" \
    "$WEB_IMAGE" >/dev/null

  run docker exec "$web" nginx -t
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  assert_healthy

  old_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$app")"
  web_start="$(docker inspect --format '{{.State.StartedAt}}' "$web")"
  docker rm -f "$app" >/dev/null

  # Occupy the previous address so Docker allocates another one to PHP-FPM.
  docker run -d --name "$holder" --network "$network" --ip "$old_ip" \
    "$FPM_IMAGE" sleep 180 >/dev/null
  start_app

  new_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$app")"
  [ "$old_ip" != "$new_ip" ] || { echo "PHP-FPM IP did not change" >&2; return 1; }
  assert_healthy
  [ "$web_start" = "$(docker inspect --format '{{.State.StartedAt}}' "$web")" ] || {
    echo "nginx container unexpectedly restarted" >&2
    return 1
  }
}

@test "nginx denies direct access to dependency and shipped metadata" {
  start_app
  docker run -d --name "$web" --network "$network" \
    --volume "$workdir/htdocs:/var/www/html:ro" \
    --volume "$workdir/includes:/etc/nginx/conf.d/includes:ro" \
    "$WEB_IMAGE" >/dev/null

  assert_healthy
  for file in composer.json composer.lock package.json package-lock.json core/shipped.json; do
    run docker exec "$web" wget -S -O /dev/null "http://127.0.0.1/$file"
    [ "$status" -ne 0 ] || { echo "$file was served" >&2; return 1; }
    [[ "$output" == *"404 Not Found"* ]] || { echo "$file: $output" >&2; return 1; }
  done

  run docker exec "$web" nginx -t
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  [[ "$output" != *"duplicate extension"* ]] || { echo "$output" >&2; return 1; }
}
