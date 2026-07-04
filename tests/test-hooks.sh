#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

bin_dir="$tmp_root/bin"
work_dir="$tmp_root/work"
backup_dir="$tmp_root/backups"
nextcloud_dir="$tmp_root/nextcloud"
log_file="$tmp_root/php.log"
dump_output="$tmp_root/pg_dump.out"

mkdir -p "$bin_dir" "$work_dir" "$backup_dir" "$nextcloud_dir"

cat > "$bin_dir/php" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file=${HOOK_TEST_LOG_FILE:?}

printf 'php %s\n' "$*" >> "$log_file"

case "${1:-}" in
  occ)
    shift
    case "${1:-}" in
      maintenance:mode)
        exit 0
        ;;
      app:list)
        printf 'app1\napp2\n'
        exit 0
        ;;
      db:add-missing-columns|db:add-missing-indices|db:add-missing-primary-keys|maintenance:repair|config:system:set|app:update)
        exit 0
        ;;
      *)
        printf 'unexpected occ command: %s\n' "$*" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    printf 'unexpected php invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

cat > "$bin_dir/pg_dump" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "CREATE TABLE test();"
EOF

chmod +x "$bin_dir/php" "$bin_dir/pg_dump"

export PATH="$bin_dir:$PATH"
export HOOK_TEST_LOG_FILE="$log_file"
export NEXTCLOUD_DIR="$nextcloud_dir"
export NEXTCLOUD_BACKUP_DIR="$backup_dir"
export NEXTCLOUD_UPGRADE_MIN_FREE_MB=1
export POSTGRES_PASSWORD="secret"

cp "$repo_root/app-hooks/pre-upgrade/01-check-disk-and-dump-db.sh" "$work_dir/"
cp "$repo_root/app-hooks/post-upgrade/01-run-post-upgrade-commands.sh" "$work_dir/"

pushd "$work_dir" >/dev/null
bash ./01-check-disk-and-dump-db.sh
popd >/dev/null

test -f "$backup_dir/nextcloud-db.sql.gz"
test ! -f "$backup_dir/nextcloud-db.sql.gz.tmp"
gzip -dc "$backup_dir/nextcloud-db.sql.gz" > "$dump_output"
grep -q "CREATE TABLE test();" "$dump_output"

grep -q "php occ maintenance:mode --on" "$log_file"
grep -q "php occ maintenance:mode --off" "$log_file"
grep -q "php occ app:list" "$log_file"

: > "$log_file"

pushd "$work_dir" >/dev/null
HOOK_TEST_LOG_FILE="$log_file" bash ./01-run-post-upgrade-commands.sh
popd >/dev/null

test -f "$backup_dir/app_list.new"
grep -q "php occ db:add-missing-columns" "$log_file"
grep -q "php occ maintenance:mode --off" "$log_file"

echo "hook tests passed"
