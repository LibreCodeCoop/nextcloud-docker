#!/usr/bin/env bash
set -euo pipefail

# Run the built web image against a disposable FPM backend to reproduce
# the container-IP change that otherwise leaves nginx returning HTTP 502.
WEB_IMAGE="${WEB_IMAGE:?Set WEB_IMAGE to the locally built web image}"
FPM_IMAGE="${FPM_IMAGE:-php:8.4-fpm-alpine}"
test_id="nc-fpm-dns-$$"
network="$test_id"
web="$test_id-web"
app="$test_id-app"
holder="$test_id-holder"
workdir="$(mktemp -d)"

cleanup() {
  docker rm -f "$web" "$app" "$holder" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  rm -rf "$workdir"
}
trap cleanup EXIT

mkdir -p "$workdir/htdocs" "$workdir/includes"
chmod 755 "$workdir"
printf '%s\n' "<?php echo 'healthy';" > "$workdir/htdocs/status.php"

docker network create "$network" >/dev/null

start_app() {
  docker run --detach --name "$app" --network "$network" --network-alias app \
    --volume "$workdir/htdocs:/var/www/html:ro" "$FPM_IMAGE" >/dev/null
}

read_status() {
  docker exec "$web" wget -q -T 3 -O - http://127.0.0.1/status.php 2>/dev/null
}

wait_for_status() {
  local attempt response
  for ((attempt = 0; attempt < 30; attempt++)); do
    if response="$(read_status)" && [[ "$response" == "healthy" ]]; then
      return 0
    fi
    sleep 1
  done
  docker logs --tail 25 "$web" >&2
  echo "nginx did not recover access to PHP-FPM" >&2
  return 1
}

start_app
docker run --detach --name "$web" --network "$network" \
  --volume "$workdir/htdocs:/var/www/html:ro" \
  --volume "$workdir/includes:/etc/nginx/conf.d/includes:ro" \
  "$WEB_IMAGE" >/dev/null

docker exec "$web" nginx -t
wait_for_status

old_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$app")"
web_id="$(docker inspect --format '{{.Id}}' "$web")"
docker rm -f "$app" >/dev/null
# Hold the former IP so Docker must assign a different one to the replacement.
docker run --detach --name "$holder" --network "$network" --ip "$old_ip" \
  "$FPM_IMAGE" sleep 180 >/dev/null
start_app
new_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$app")"

[[ "$old_ip" != "$new_ip" ]] || { echo "FPM IP did not change" >&2; exit 1; }
wait_for_status
[[ "$(docker inspect --format '{{.Id}}' "$web")" == "$web_id" ]] || {
  echo "nginx container was restarted" >&2
  exit 1
}

echo "nginx recovered without reload after FPM changed from $old_ip to $new_ip"
