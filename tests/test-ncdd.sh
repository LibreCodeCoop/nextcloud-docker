#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ncdd=(bash "$repo_root/bin/ncdd")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/project" "$tmp/bin"

cat > "$tmp/project/.ncdd.yml" <<'YAML'
nextcloud:
  default: 35
app:
  id: demo
  source: .
  path: /var/www/html/apps-extra/demo
  runtime_user: www-data
services:
  app: app
  worker: dev-worker
http:
  port: 8888
YAML

cat > "$tmp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >> "${NCDD_TEST_LOG:?}"
printf '\n' >> "${NCDD_TEST_LOG:?}"
if [ "${1:-}" = compose ] && [ "${2:-}" = version ]; then exit 0; fi
case " $* " in
  *" ps --status running --services "*) printf 'app\ndev-worker\n'; exit 0 ;;
  *" php occ status --output=json "*) printf '{"installed":true}\n'; exit 0 ;;
esac
exit 0
MOCK
chmod +x "$tmp/bin/docker"

export PATH="$tmp/bin:$PATH"
export NCDD_TEST_LOG="$tmp/docker.log"

out=$(cd "$tmp/project" && "${ncdd[@]}" env)
grep -q '^NCDD_NEXTCLOUD_REF=stable35$' <<<"$out"
grep -q '^NCDD_NEXTCLOUD_MAJOR=35$' <<<"$out"
grep -q '^NCDD_APP_ID=demo$' <<<"$out"
grep -q '^NCDD_HTTP_PORT=8888$' <<<"$out"
grep -q '^NCDD_APP_IMAGE=ghcr.io/librecodecoop/nextcloud-docker-app:35$' <<<"$out"
grep -q '^NCDD_DEV_WORKER_IMAGE=ghcr.io/librecodecoop/nextcloud-docker-dev-worker:35$' <<<"$out"

json=$(cd "$tmp/project" && "${ncdd[@]}" doctor --json)
grep -q '"ready":true' <<<"$json"
grep -q '"ref":"stable35"' <<<"$json"

(cd "$tmp/project" && "${ncdd[@]}" exec --as runtime -- php -v)
grep -q -- '--user www-data dev-worker php -v' "$tmp/docker.log"

help=$("${ncdd[@]}" help ai)
grep -q 'Do not call docker compose directly' <<<"$help"

list=$(cd "$tmp/project" && "${ncdd[@]}" test --list)
grep -q '^phpunit$' <<<"$list"
grep -q '^full$' <<<"$list"

(cd "$tmp/project" && "${ncdd[@]}" test phpunit tests/php/Unit/FooTest.php)
grep -q 'dev-worker sh -lc' "$tmp/docker.log"
grep -q 'vendor/bin/phpunit' "$tmp/docker.log"

(cd "$tmp/project" && "${ncdd[@]}" test frontend lint)
grep -q 'node-worker sh -lc' "$tmp/docker.log"

json_test=$(cd "$tmp/project" && "${ncdd[@]}" test --json phpunit tests/php/Unit/FooTest.php 2>/dev/null)
grep -q '"suite":"phpunit"' <<<"$json_test"
grep -q '"status":0' <<<"$json_test"

bash -n "$repo_root/bin/ncdd"
bash -n "$repo_root/lib/ncdd-tests.sh"
echo 'ncdd CLI tests passed'
