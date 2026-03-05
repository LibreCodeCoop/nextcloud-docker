#!/bin/bash
set -euo pipefail

# Run required maintenance tasks after a Nextcloud upgrade.
run_occ() {
    local cmd="$1"
    echo "[post-upgrade] Running: php occ ${cmd}"
    php occ ${cmd}
    echo "[post-upgrade] Success: php occ ${cmd}"
}

run_occ "db:add-missing-columns"
run_occ "db:add-missing-indices"
run_occ "db:add-missing-primary-keys"
run_occ "maintenance:repair --include-expensive"
run_occ "app:update --all"
run_occ "upgrade"
