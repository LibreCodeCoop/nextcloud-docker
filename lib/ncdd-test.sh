# shellcheck shell=bash

ncdd_test_usage() {
  cat <<'EOF'
Usage:
  ncdd test --list
  ncdd test phpunit --app APP [-- PHPUnit arguments...]
  ncdd test behat --app APP [-- Behat arguments...]

The app must already exist under /var/www/html/apps-extra/ in the existing
NCDD stack. NCDD does not clone or install application source code.
EOF
}

ncdd_test_list() {
  printf '%s\n' phpunit behat
}

ncdd_test_validate_app() {
  local app=$1

  if [[ ! "$app" =~ ^[A-Za-z0-9._-]+$ ]]; then
    fail "invalid app id: $app"
  fi
}

ncdd_test_parse_app() {
  local app=''

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --app)
        [ "$#" -ge 2 ] || fail "--app requires a value"
        app=$2
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done

  if [ -z "$app" ]; then
    app=${NCDD_TEST_APP:-}
  fi
  [ -n "$app" ] || fail "test suite requires --app APP or NCDD_TEST_APP"

  ncdd_test_validate_app "$app"

  NCDD_TEST_RESOLVED_APP=$app
  NCDD_TEST_REMAINING_ARGS=("$@")
}

ncdd_test_phpunit() {
  ncdd_test_parse_app "$@"

  local app_dir="/var/www/html/apps-extra/$NCDD_TEST_RESOLVED_APP"
  local user=${NCDD_PHPUNIT_USER:-root}

  compose exec -T \
    --user "$user" \
    --workdir "$app_dir" \
    "$APP_SERVICE" \
    vendor/bin/phpunit \
    "${NCDD_TEST_REMAINING_ARGS[@]}"
}

ncdd_test_behat() {
  ncdd_test_parse_app "$@"

  local app_dir="/var/www/html/apps-extra/$NCDD_TEST_RESOLVED_APP"
  local integration_dir="$app_dir/${NCDD_BEHAT_DIR:-tests/integration}"

  compose exec -T \
    --user "$RUNTIME_USER" \
    --workdir "$integration_dir" \
    -e BEHAT_ROOT_DIR=/var/www/html \
    -e "BEHAT_RUN_AS=$RUNTIME_USER" \
    -e "BEHAT_VERBOSE=${BEHAT_VERBOSE:-1}" \
    "$APP_SERVICE" \
    vendor/bin/behat \
    "${NCDD_TEST_REMAINING_ARGS[@]}"
}

ncdd_test() {
  case "${1:-}" in
    --list)
      [ "$#" -eq 1 ] || fail "test --list does not accept extra arguments"
      ncdd_test_list
      ;;
    -h|--help|'')
      ncdd_test_usage
      ;;
    phpunit)
      shift
      ncdd_test_phpunit "$@"
      ;;
    behat)
      shift
      ncdd_test_behat "$@"
      ;;
    *)
      fail "unknown test suite: $1"
      ;;
  esac
}
