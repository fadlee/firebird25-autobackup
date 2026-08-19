#!/bin/bash
set -euo pipefail

ENV_FILE=/etc/firebird-backup.env
LOG_DIR=/var/log
CRON_FILE=/etc/cron.d/firebird-backup

log() { echo "[backup-wrapper] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# --- Tulis konfigurasi backup ke file, supaya bisa dibaca cron job -----------
# (proses cron tidak mewarisi environment variable container secara otomatis)
cat > "$ENV_FILE" <<EOF
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
BACKUP_DATABASES=${BACKUP_DATABASES:-}
BACKUP_ROLE=${BACKUP_ROLE:-RDB\$ADMIN}
# export supaya kelihatan subproses (date di log()/nama file) — source biasa
# cuma bikin shell var non-export, dan shell cron tidak mewarisi TZ container
export TZ=${TZ:-UTC}
EOF
# Kredensial backup ditulis shell-escaped; password tidak pernah ditampilkan di log.
printf 'BACKUP_USER=%q\nBACKUP_PASSWORD=%q\n' "${BACKUP_USER:-}" "${BACKUP_PASSWORD:-}" >> "$ENV_FILE"
chmod 600 "$ENV_FILE"

# --- Pasang jadwal cron -------------------------------------------------------
touch "${LOG_DIR}/firebird-backup.log"
echo "${BACKUP_CRON:-0 2 * * *} root /usr/local/bin/backup.sh >> ${LOG_DIR}/firebird-backup.log 2>&1" > "$CRON_FILE"
chmod 0644 "$CRON_FILE"
log "Jadwal auto-backup: ${BACKUP_CRON:-0 2 * * *} (retensi ${BACKUP_RETENTION_DAYS:-7} hari)"
if [ -n "${BACKUP_PASSWORD:-}" ]; then
    BACKUP_PASSWORD_STATUS=diset
else
    BACKUP_PASSWORD_STATUS=dari-SYSDBA.password
fi
log "Env backup (ubah via environment): BACKUP_CRON='${BACKUP_CRON:-0 2 * * *}' (jadwal) | BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7} (hari) | BACKUP_DATABASES='${BACKUP_DATABASES:-}' (kosong=semua *.fdb) | BACKUP_USER='${BACKUP_USER:-SYSDBA}' | BACKUP_ROLE='${BACKUP_ROLE:-RDB\$ADMIN}' | BACKUP_PASSWORD=${BACKUP_PASSWORD_STATUS} | TZ='${TZ:-UTC}'"

cron

# Volume lama bisa hanya berisi security2.fdb. Entrypoint upstream lalu
# melewati init, padahal config/password belum ada.
if [ -f /firebird/system/security2.fdb ] && [ ! -f /firebird/etc/firebird.conf ]; then
    log "Volume Firebird tidak lengkap: melengkapi konfigurasi dari skeleton"
    mkdir -p /firebird/etc
    for file in /usr/local/firebird/skel/etc/*; do
        [ "$(basename "$file")" = SYSDBA.password ] || cp -n "$file" /firebird/etc/
    done
    if [ ! -f /firebird/etc/SYSDBA.password ]; then
        if [ -z "${ISC_PASSWORD:-}" ]; then
            log "GAGAL: ISC_PASSWORD wajib diisi untuk melengkapi volume lama"
            exit 1
        fi
        printf 'ISC_USER=SYSDBA\nISC_PASSWD=%s\nISC_PASSWORD=%s\n' \
            "$ISC_PASSWORD" "$ISC_PASSWORD" > /firebird/etc/SYSDBA.password
        chmod 400 /firebird/etc/SYSDBA.password
    fi
fi

# Volume lama juga dapat berisi pidfile stale dari container sebelumnya.
rm -f /var/run/firebird/firebird.pid

# --- Lanjut ke entrypoint asli image jacobalberty/firebird -------------------
# Ini yang menjalankan setup SYSDBA, create database, restore dari
# /firebird/restore, dan start fbguard/fbserver seperti biasa. Argumen
# (CMD) diteruskan apa adanya.
exec /usr/local/firebird/docker-entrypoint.sh "$@"
