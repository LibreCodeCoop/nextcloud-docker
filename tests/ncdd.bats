#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  TMP_ROOT=$(mktemp -d)
  mkdir -p "$TMP_ROOT/bin"
  export NCDD_TEST_LOG="$TMP_ROOT/docker.log"

  cat > "$TMP_ROOT/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "${NCDD_TEST_LOG:?}"
printf '\n' >> "${NCDD_TEST_LOG:?}"

if [ "${1:-}" = "compose" ] && [ "${2:-}" = "version" ]; then
  exit 0
fi

case " $* " in
  *" ps --status running --services "*)
    printf 'app\nredis\npostgres\n'
    ;;
  *" php occ status --output=json "*)
    printf '{"installed":true}\n'
    ;;
esac
MOCK
  chmod +x "$TMP_ROOT/bin/docker"
  export PATH="$TMP_ROOT/bin:$PATH"
}

teardown() {
  rm -rf "$TMP_ROOT"
}

@test "help documents the supported interface" {
  run bash "$REPO_ROOT/bin/ncdd" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"doctor [--json]"* ]]
  [[ "$output" == *"exec [--as USER]"* ]]
}

@test "env reads the existing repository version source" {
  run bash "$REPO_ROOT/bin/ncdd" env
  [ "$status" -eq 0 ]
  [[ "$output" == *"NEXTCLOUD_VERSION=34-fpm"* ]]
}

@test "doctor exposes a machine-readable healthy state" {
  run bash "$REPO_ROOT/bin/ncdd" doctor --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ready":true'* ]]
  [[ "$output" == *'"nextcloud_ready":true'* ]]
}

@test "runtime alias maps to www-data in the existing app service" {
  run bash "$REPO_ROOT/bin/ncdd" exec --as runtime -- php -v
  [ "$status" -eq 0 ]
  grep -q -- '--user www-data app php -v' "$NCDD_TEST_LOG"
}

@test "up uses the existing compose files and required external networks" {
  run bash "$REPO_ROOT/bin/ncdd" up
  [ "$status" -eq 0 ]
  grep -q 'network inspect reverse-proxy' "$NCDD_TEST_LOG"
  grep -q 'network inspect postgres' "$NCDD_TEST_LOG"
  grep -q -- "-f $REPO_ROOT/docker-compose.yml" "$NCDD_TEST_LOG"
  grep -q -- "-f $REPO_ROOT/docker-compose-postgres.yml" "$NCDD_TEST_LOG"
  grep -q 'up -d redis postgres app web cron' "$NCDD_TEST_LOG"
}

@test "logs uses the existing compose stack" {
  run bash "$REPO_ROOT/bin/ncdd" logs app
  [ "$status" -eq 0 ]
  grep -q -- 'logs --no-color app' "$NCDD_TEST_LOG"
}

@test "agent help keeps Docker Compose as an implementation detail" {
  run bash "$REPO_ROOT/bin/ncdd" help ai
  [ "$status" -eq 0 ]
  [[ "$output" == *"Use bin/ncdd instead of calling docker compose directly."* ]]
}

@test "test --list exposes supported suites" {
  run bash "$REPO_ROOT/bin/ncdd" test --list
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'phpunit\nbehat')" ]
}

@test "phpunit test runs in the selected app without shell evaluation" {
  run bash "$REPO_ROOT/bin/ncdd" test phpunit --app libresign -- -c tests/php/phpunit.xml tests/php/Unit/FooTest.php
  [ "$status" -eq 0 ]
  grep -q -- '--user root --workdir /var/www/html/apps-extra/libresign app vendor/bin/phpunit -c tests/php/phpunit.xml tests/php/Unit/FooTest.php' "$NCDD_TEST_LOG"
}

@test "behat test applies the Nextcloud runtime contract" {
  run bash "$REPO_ROOT/bin/ncdd" test behat --app libresign -- features/file/validate.feature
  [ "$status" -eq 0 ]
  grep -q -- '--user www-data --workdir /var/www/html/apps-extra/libresign/tests/integration' "$NCDD_TEST_LOG"
  grep -q -- '-e BEHAT_ROOT_DIR=/var/www/html' "$NCDD_TEST_LOG"
  grep -q -- '-e BEHAT_RUN_AS=www-data' "$NCDD_TEST_LOG"
  grep -q -- 'app vendor/bin/behat features/file/validate.feature' "$NCDD_TEST_LOG"
}

@test "test command rejects path traversal in app id" {
  run bash "$REPO_ROOT/bin/ncdd" test phpunit --app ../libresign
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid app id"* ]]
}

@test "CLI and test module are valid Bash" {
  run bash -n "$REPO_ROOT/bin/ncdd"
  [ "$status" -eq 0 ]

  run bash -n "$REPO_ROOT/lib/ncdd-test.sh"
  [ "$status" -eq 0 ]
}