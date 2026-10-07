# shellcheck shell=bash

ncdd_test_usage() {
  cat <<'EOF_USAGE'
Usage: ncdd test [--json] --list
       ncdd test [--json] phpunit [TARGET]
       ncdd test [--json] behat [TARGET]
       ncdd test [--json] frontend [lint|types|unit|all]
       ncdd test [--json] full
EOF_USAGE
}

ncdd_test_suites() {
  printf '%s\n' phpunit behat frontend-lint frontend-types frontend-unit full
}

ncdd_exec_service_shell() {
  local service=$1 user=$2 workdir=$3 command=$4
  compose exec -T --user "$user" --workdir "$workdir" "$service" sh -lc "$command"
}

ncdd_shell_quote() {
  printf '%q' "$1"
}

ncdd_test_run() {
  local suite=$1
  shift || true

  local node_service phpunit_dir phpunit_cmd phpunit_user
  local behat_dir behat_cmd behat_user frontend_dir
  node_service=$(cfg services.node)
  [ -n "$node_service" ] || node_service=node-worker

  phpunit_dir=$(cfg tests.phpunit.working_directory)
  [ -n "$phpunit_dir" ] || phpunit_dir="$APP_PATH"
  phpunit_cmd=$(cfg tests.phpunit.command)
  [ -n "$phpunit_cmd" ] || phpunit_cmd='vendor/bin/phpunit -c tests/php/phpunit.xml'
  phpunit_user=$(cfg tests.phpunit.user)
  [ -n "$phpunit_user" ] || phpunit_user=root
  phpunit_user=$(resolve_user "$phpunit_user")

  behat_dir=$(cfg tests.behat.working_directory)
  [ -n "$behat_dir" ] || behat_dir="$APP_PATH/tests/integration"
  behat_cmd=$(cfg tests.behat.command)
  [ -n "$behat_cmd" ] || behat_cmd='vendor/bin/behat'
  behat_user=$(cfg tests.behat.user)
  [ -n "$behat_user" ] || behat_user=runtime
  behat_user=$(resolve_user "$behat_user")

  frontend_dir=$(cfg tests.frontend.working_directory)
  [ -n "$frontend_dir" ] || frontend_dir=/workspace/app

  case "$suite" in
    phpunit)
      local command=$phpunit_cmd
      if [ "$#" -gt 0 ]; then command+=" $(ncdd_shell_quote "$1")"; fi
      ncdd_exec_service_shell "$WORKER_SERVICE" "$phpunit_user" "$phpunit_dir" "$command"
      ;;
    behat)
      local command=$behat_cmd
      if [ "$#" -gt 0 ]; then command+=" $(ncdd_shell_quote "$1")"; fi
      ncdd_exec_service_shell "$WORKER_SERVICE" "$behat_user" "$behat_dir" "$command"
      ;;
    frontend)
      local mode=${1:-all}
      case "$mode" in
        lint) ncdd_exec_service_shell "$node_service" root "$frontend_dir" 'npm run lint' ;;
        types) ncdd_exec_service_shell "$node_service" root "$frontend_dir" 'npm run ts:check' ;;
        unit) ncdd_exec_service_shell "$node_service" root "$frontend_dir" 'npm test' ;;
        all)
          ncdd_exec_service_shell "$node_service" root "$frontend_dir" 'npm run lint'
          ncdd_exec_service_shell "$node_service" root "$frontend_dir" 'npm run ts:check'
          ;;
        *) fail "unknown frontend test mode: $mode" ;;
      esac
      ;;
    full)
      ncdd_test_run phpunit
      ncdd_test_run behat
      ncdd_test_run frontend all
      ;;
    *)
      fail "unknown test suite: $suite"
      ;;
  esac
}

ncdd_test() {
  local json=false
  if [ "${1:-}" = "--json" ]; then json=true; shift; fi
  if [ "${1:-}" = "--list" ]; then ncdd_test_suites; return 0; fi
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -eq 0 ]; then ncdd_test_usage; return 0; fi

  local suite=$1
  shift

  if ! $json; then
    ncdd_test_run "$suite" "$@"
    return
  fi

  local output status started finished
  started=$(date +%s)
  set +e
  output=$(ncdd_test_run "$suite" "$@" 2>&1)
  status=$?
  set -e
  finished=$(date +%s)
  printf '%s\n' "$output" >&2
  printf '{"suite":"%s","status":%d,"duration_seconds":%d}\n' "$suite" "$status" "$((finished-started))"
  return "$status"
}

ncdd_scenario_scalar() {
  local key=$1 file=$2
  awk -v key="$key" '
    $0 ~ "^" key ":[[:space:]]*" {
      sub("^" key ":[[:space:]]*", "")
      gsub(/^[ \t\047\"]+|[ \t\047\"]+$/, "")
      print
      exit
    }
  ' "$file"
}

ncdd_scenario_lines() {
  local section=$1 file=$2
  awk -v wanted="$section" '
    /^[^[:space:]][^:]*:/ {
      section=$0
      sub(/:.*/, "", section)
      next
    }
    section==wanted && /^[[:space:]]*-[[:space:]]+/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]+/, "", line)
      gsub(/^\047|\047$/, "", line)
      gsub(/^\"|\"$/, "", line)
      print line
    }
  ' "$file"
}

ncdd_scenario() {
  [ "${1:-}" = run ] || fail "usage: ncdd scenario run FILE"
  shift

  local file=${1:?scenario file required}
  [[ "$file" = /* ]] || file="$PROJECT_ROOT/$file"
  [ -f "$file" ] || fail "scenario not found: $file"

  local ref
  ref=$(ncdd_scenario_scalar nextcloud "$file")
  [ -n "$ref" ] || ref="$NEXTCLOUD_REF"

  local runner=(bash "$NCDD_ROOT/bin/ncdd" --project-root "$PROJECT_ROOT" --config "$CONFIG_FILE" --source "$APP_SOURCE" --app-id "$APP_ID" --nextcloud "$ref")
  "${runner[@]}" up

  local status=0
  trap '"${runner[@]}" down >/dev/null 2>&1 || true' RETURN

  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    "${runner[@]}" exec -- sh -lc "$line" || { status=$?; break; }
  done < <(ncdd_scenario_lines setup "$file")

  if [ "$status" -eq 0 ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      local suite=${line%% *}
      local target=''
      if [[ "$line" == *' '* ]]; then target=${line#* }; fi
      if [ -n "$target" ]; then
        "${runner[@]}" test "$suite" "$target" || { status=$?; break; }
      else
        "${runner[@]}" test "$suite" || { status=$?; break; }
      fi
    done < <(ncdd_scenario_lines tests "$file")
  fi

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    "${runner[@]}" exec -- sh -lc "$line" || status=$?
  done < <(ncdd_scenario_lines teardown "$file")

  "${runner[@]}" down >/dev/null 2>&1 || true
  trap - RETURN
  return "$status"
}
