#!/bin/bash
set -euo pipefail

BACKUP_ROOT="${PRE_UPGRADE_BACKUP_ROOT:-/var/www/html/data/pre-upgrade-backups}"
MIN_FREE_MB="${PRE_UPGRADE_MIN_FREE_MB:-2048}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

log() {
    echo "[pre-upgrade] $*"
}

run_occ() {
    local cmd="$1"
    log "Running: php occ ${cmd}"
    php occ ${cmd}
    log "Success: php occ ${cmd}"
}

log "Starting pre-upgrade checks"
run_occ "status"

FREE_MB="$(df -Pm /var/www/html | awk 'NR==2 {print $4}')"
if [ -z "${FREE_MB}" ]; then
    log "Could not determine free disk space"
    exit 1
fi

if [ "${FREE_MB}" -lt "${MIN_FREE_MB}" ]; then
    log "Insufficient disk space: ${FREE_MB}MB free, required at least ${MIN_FREE_MB}MB"
    exit 1
fi
log "Disk space check passed: ${FREE_MB}MB free"

run_occ "maintenance:mode --on"

mkdir -p "${BACKUP_DIR}"
log "Backup directory created: ${BACKUP_DIR}"

if [ -f /var/www/html/config/config.php ]; then
    cp /var/www/html/config/config.php "${BACKUP_DIR}/config.php"
    log "Saved config backup: ${BACKUP_DIR}/config.php"
fi

php occ app:list > "${BACKUP_DIR}/app-list.txt"
log "Saved app list: ${BACKUP_DIR}/app-list.txt"

if [ -d /var/www/html/apps-extra ]; then
    tar -czf "${BACKUP_DIR}/apps-extra.tar.gz" -C /var/www/html apps-extra
    log "Saved apps-extra backup: ${BACKUP_DIR}/apps-extra.tar.gz"
fi

if command -v pg_dump >/dev/null 2>&1 && [ -n "${POSTGRES_HOST:-}" ] && [ -n "${POSTGRES_DB:-}" ] && [ -n "${POSTGRES_USER:-}" ] && [ -n "${POSTGRES_PASSWORD:-}" ]; then
    PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" "${POSTGRES_DB}" > "${BACKUP_DIR}/postgres.sql"
    log "Saved database backup: ${BACKUP_DIR}/postgres.sql"
else
    log "Skipping database backup (pg_dump or PostgreSQL env vars not available)"
fi

log "Pre-upgrade checks completed successfully"
