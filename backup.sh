#!/bin/bash
set -euo pipefail

PREFIX=/usr/local/firebird
DATA_DIR=/firebird/data
BACKUP_DIR=/firebird/backups
PASSWORD_FILE=/firebird/etc/SYSDBA.password
ENV_FILE=/etc/firebird-backup.env

mkdir -p "$BACKUP_DIR"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# Ambil kredensial SYSDBA yang di-generate/di-set oleh entrypoint asli
# (berisi export ISC_USER dan ISC_PASSWORD)
if [ -f "$PASSWORD_FILE" ]; then
    source "$PASSWORD_FILE"
else
    echo "[backup] $(date '+%Y-%m-%d %H:%M:%S') GAGAL: ${PASSWORD_FILE} tidak ditemukan, server mungkin belum selesai init"
    exit 1
fi

RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

log() { echo "[backup] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Daftar database: dari BACKUP_DATABASES (comma-separated) atau auto-discover
# semua *.fdb di /firebird/data
if [ -n "${BACKUP_DATABASES:-}" ]; then
    IFS=',' read -ra DB_LIST <<< "$BACKUP_DATABASES"
else
    DB_LIST=()
    while IFS= read -r -d '' f; do
        DB_LIST+=("$(basename "$f")")
    done < <(find "$DATA_DIR" -maxdepth 1 -name '*.fdb' -print0)
fi

if [ ${#DB_LIST[@]} -eq 0 ]; then
    log "Tidak ada database ditemukan untuk di-backup (cek BACKUP_DATABASES atau isi $DATA_DIR)"
    exit 0
fi

FAILED=0

for DB_NAME in "${DB_LIST[@]}"; do
    DB_NAME=$(echo "$DB_NAME" | xargs)
    DB_PATH="${DATA_DIR}/${DB_NAME}"
    BASE_NAME="${DB_NAME%.fdb}"
    OUT_FILE="${BACKUP_DIR}/${BASE_NAME}_${TIMESTAMP}.fbk"

    if [ ! -f "$DB_PATH" ]; then
        log "SKIP: $DB_PATH tidak ditemukan"
        continue
    fi

    log "Backup $DB_PATH -> $OUT_FILE"
    if "${PREFIX}/bin/gbak" -b -user "${ISC_USER:-sysdba}" -password "${ISC_PASSWORD}" \
        -garbage_collect -ignore -verbose "$DB_PATH" "$OUT_FILE" \
        > "${BACKUP_DIR}/${BASE_NAME}_${TIMESTAMP}.log" 2>&1; then
        gzip -f "$OUT_FILE"
        log "OK: $(basename "$OUT_FILE").gz"
        rm -f "${BACKUP_DIR}/${BASE_NAME}_${TIMESTAMP}.log"
    else
        log "GAGAL backup $DB_NAME, lihat ${BASE_NAME}_${TIMESTAMP}.log"
        FAILED=1
    fi
done

# --- Rotasi: hapus backup lebih tua dari retention days ---------------------
log "Membersihkan backup lebih tua dari ${RETENTION_DAYS} hari"
find "$BACKUP_DIR" -maxdepth 1 -name '*.fbk.gz' -mtime "+${RETENTION_DAYS}" -print -delete
find "$BACKUP_DIR" -maxdepth 1 -name '*.log' -mtime "+${RETENTION_DAYS}" -print -delete

if [ "$FAILED" -eq 1 ]; then
    log "Selesai dengan beberapa kegagalan"
    exit 1
fi
log "Semua backup selesai"
