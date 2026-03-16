#!/bin/bash
set -euo pipefail

BACKUP_ROOT="${PRE_UPGRADE_BACKUP_ROOT:-/var/www/html/data/pre-upgrade-backups}"
MIN_FREE_MB="${PRE_UPGRADE_MIN_FREE_MB:-2048}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

log() {
    echo "[pre-upgrade] $*"
}

read_nextcloud_db_config() {
    php <<'PHP'
<?php
$config = include '/var/www/html/config/config.php';
if (!is_array($config)) {
    exit(1);
}

$keys = ['dbtype', 'dbname', 'dbhost', 'dbport', 'dbuser', 'dbpassword'];
foreach ($keys as $key) {
    $value = $config[$key] ?? '';
    if (is_array($value)) {
        $value = '';
    }
    echo $value, PHP_EOL;
}
PHP
}

parse_db_host() {
    DB_HOST="${1:-}"
    DB_PORT="${2:-}"

    if [ -z "${DB_PORT}" ] && [[ "${DB_HOST}" == *:* ]] && [[ "${DB_HOST}" != \[*\] ]]; then
        DB_PORT="${DB_HOST##*:}"
        DB_HOST="${DB_HOST%%:*}"
    fi
}

backup_database() {
    local db_type db_name db_host_raw db_port_raw db_user db_password dump_path engine_label
    local db_config=()

    if [ ! -f /var/www/html/config/config.php ]; then
        log "Skipping database backup (config.php not found)"
        return 0
    fi

    if ! mapfile -t db_config < <(read_nextcloud_db_config); then
        log "Skipping database backup (failed to read database config)"
        return 0
    fi

    db_type="${db_config[0]:-}"
    db_name="${db_config[1]:-}"
    db_host_raw="${db_config[2]:-}"
    db_port_raw="${db_config[3]:-}"
    db_user="${db_config[4]:-}"
    db_password="${db_config[5]:-}"

    if [ -z "${db_type}" ] || [ -z "${db_name}" ] || [ -z "${db_user}" ]; then
        log "Skipping database backup (database config is incomplete)"
        return 0
    fi

    parse_db_host "${db_host_raw}" "${db_port_raw}"

    case "${db_type}" in
        pgsql)
            if ! command -v pg_dump >/dev/null 2>&1; then
                log "Skipping database backup (pg_dump is not installed)"
                return 0
            fi

            if [ -z "${DB_HOST}" ] || [ -z "${db_password}" ]; then
                log "Skipping database backup (PostgreSQL host or password is missing)"
                return 0
            fi

            dump_path="${BACKUP_DIR}/postgres.sql"
            engine_label="PostgreSQL"
            if [ -n "${DB_PORT}" ]; then
                PGPASSWORD="${db_password}" pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${db_user}" "${db_name}" > "${dump_path}"
            else
                PGPASSWORD="${db_password}" pg_dump -h "${DB_HOST}" -U "${db_user}" "${db_name}" > "${dump_path}"
            fi
            ;;
        mysql|mysqli)
            if ! command -v mysqldump >/dev/null 2>&1; then
                log "Skipping database backup (mysqldump is not installed)"
                return 0
            fi

            if [ -z "${DB_HOST}" ] || [ -z "${db_password}" ]; then
                log "Skipping database backup (MySQL/MariaDB host or password is missing)"
                return 0
            fi

            dump_path="${BACKUP_DIR}/mysql.sql"
            engine_label="MySQL/MariaDB"
            if [ -n "${DB_PORT}" ]; then
                mysqldump --host="${DB_HOST}" --port="${DB_PORT}" --user="${db_user}" --password="${db_password}" --single-transaction --quick "${db_name}" > "${dump_path}"
            else
                mysqldump --host="${DB_HOST}" --user="${db_user}" --password="${db_password}" --single-transaction --quick "${db_name}" > "${dump_path}"
            fi
            ;;
        sqlite3)
            log "Skipping database backup (sqlite3 is not supported by this hook)"
            return 0
            ;;
        *)
            log "Skipping database backup (unsupported database type: ${db_type})"
            return 0
            ;;
    esac

    log "Saved ${engine_label} database backup: ${dump_path}"
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

backup_database

log "Pre-upgrade checks completed successfully"
