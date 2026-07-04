#!/bin/bash

set -euo pipefail

backup_dir=${NEXTCLOUD_BACKUP_DIR:-/backups}

cleanup() {
    php occ maintenance:mode --off >/dev/null 2>&1 || true
}

trap cleanup EXIT

run_occ() {
    echo "Running: php occ $*"
    php occ "$@"
}

echo "Running post-upgrade Nextcloud commands"
php occ app:list > "$backup_dir/app_list.new"
if [ -f "$backup_dir/app_list.old" ]; then
    echo "Comparing app lists"
    diff -u "$backup_dir/app_list.old" "$backup_dir/app_list.new" || true
fi
run_occ db:add-missing-columns
run_occ db:add-missing-indices
run_occ db:add-missing-primary-keys
run_occ maintenance:repair --include-expensive
run_occ config:system:set maintenance_window_start --type=integer --value=1
run_occ app:update --all
echo "Post-upgrade commands completed successfully"
