#!/bin/bash

set -euo pipefail

nextcloud_dir=${NEXTCLOUD_DIR:-/var/www/html}
backup_dir=${NEXTCLOUD_BACKUP_DIR:-/backups}
min_free_mb=${NEXTCLOUD_UPGRADE_MIN_FREE_MB:-2048}
db_host=${POSTGRES_HOST:-postgres}
db_name=${POSTGRES_DB:-nextcloud}
db_user=${POSTGRES_USER:-nextcloud}
db_password=${POSTGRES_PASSWORD:-}
timestamp=$(date +%Y%m%d-%H%M%S)
backup_file="${backup_dir}/nextcloud-db-${timestamp}.sql.gz"
app_list_file="${backup_dir}/app_list.old"

run_occ() {
    echo "Running: php occ $*"
    php occ "$@"
}

check_free_space() {
    local path=$1
    local label=$2
    local available_mb

    available_mb=$(df -Pm "$path" | awk 'NR==2 { print $4 }')

    if [ "$available_mb" -lt "$min_free_mb" ]; then
        echo "Not enough disk space on ${label}: ${available_mb} MB available, ${min_free_mb} MB required"
        exit 1
    fi

    echo "${label} has ${available_mb} MB free"
}

echo "Running pre-upgrade safety checks"
mkdir -p "$backup_dir"

run_occ maintenance:mode --on
php occ app:list > "$app_list_file"
echo "Saved active apps list to ${app_list_file}"

check_free_space "$nextcloud_dir" "Nextcloud volume"
check_free_space "$backup_dir" "Backup volume"

if ! command -v pg_dump >/dev/null 2>&1; then
    echo "pg_dump is not available in the container image"
    exit 1
fi

if [ -z "$db_password" ]; then
    echo "POSTGRES_PASSWORD is empty, refusing to create a database dump"
    exit 1
fi

echo "Creating PostgreSQL dump at ${backup_file}"
PGPASSWORD="$db_password" pg_dump -h "$db_host" -U "$db_user" "$db_name" | gzip -9 > "$backup_file"
echo "Database dump completed successfully"
