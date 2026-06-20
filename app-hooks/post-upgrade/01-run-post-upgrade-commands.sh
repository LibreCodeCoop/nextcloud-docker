#!/bin/bash

set -euo pipefail

run_occ() {
    echo "Running: php occ $*"
    php occ "$@"
}

echo "Running post-upgrade Nextcloud commands"
run_occ db:add-missing-columns
run_occ db:add-missing-indices
run_occ db:add-missing-primary-keys
run_occ maintenance:repair --include-expensive
run_occ config:system:set maintenance_window_start --type=integer --value=1
run_occ maintenance:mode --off
run_occ app:update --all
run_occ maintenance:mode --off
echo "Post-upgrade commands completed successfully"
