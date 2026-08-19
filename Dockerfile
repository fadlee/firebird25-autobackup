# syntax=docker/dockerfile:1
#
# Nempelin auto-backup di atas image jacobalberty/firebird:v2.5.9-ss yang sudah
# battle-tested, tanpa mengubah cara kerja instalasi Firebird-nya sama sekali.
# Entrypoint asli image ini tetap dipakai apa adanya (setup SYSDBA, create DB,
# restore dari /firebird/restore, start fbguard, dll) — kita cuma nambahin cron.

FROM jacobalberty/firebird:v2.5.9-ss

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends cron gzip \
    && rm -rf /var/lib/apt/lists/*

COPY backup.sh /usr/local/bin/backup.sh
COPY docker-entrypoint-wrapper.sh /usr/local/bin/docker-entrypoint-wrapper.sh
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/docker-entrypoint-wrapper.sh

ENV BACKUP_CRON="0 2 * * *" \
    BACKUP_RETENTION_DAYS=7 \
    BACKUP_DATABASES= \
    BACKUP_USER= \
    BACKUP_ROLE="RDB\$ADMIN"

# Pastikan folder backup ada di dalam volume /firebird yang sudah ada,
# jadi tidak perlu volume tambahan - cukup mount /firebird seperti biasa.
RUN mkdir -p /firebird/backups

# Wrapper ini yang jalan duluan: pasang cron job backup, lalu lanjut ke
# entrypoint asli image jacobalberty. CMD harus di-set ulang eksplisit:
# mendeklarasikan ENTRYPOINT di Dockerfile anak menghapus CMD warisan dari
# base image (jadinya null), padahal entrypoint asli menutup dengan
# `fbkill; $@` — tanpa CMD, fbguard tidak pernah dijalankan ulang di foreground.
#
# catatan: ini hardcode cmd base image; kalau image jacobalberty ganti cmd,
# sesuaikan di sini.
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-wrapper.sh"]
CMD ["/usr/local/firebird/bin/fbguard"]
