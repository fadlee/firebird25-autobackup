# Auto-backup wrapper untuk jacobalberty/firebird:v2.5.9-ss

Ini **bukan** image Firebird baru — ini cuma nempelin cron + `gbak` backup di
atas image `jacobalberty/firebird:v2.5.9-ss` yang biasa kamu pakai. Semua
perilaku image aslinya (setup SYSDBA, auto-create database, auto-restore dari
`/firebird/restore`, dst) tetap jalan persis sama seperti biasa — entrypoint
asli tidak diubah, cuma dibungkus.

## Isi

- `Dockerfile` — `FROM jacobalberty/firebird:v2.5.9-ss`, tambah `cron` + `gzip`.
- `docker-entrypoint-wrapper.sh` — pasang jadwal cron dulu, baru `exec` ke
  `/usr/local/firebird/docker-entrypoint.sh` (entrypoint asli image).
- `backup.sh` — jalanin `gbak -b` (logical/hot backup), pakai kredensial
  SYSDBA yang sama dengan yang di-generate/di-set image aslinya
  (`/firebird/etc/SYSDBA.password`), hasil di-gzip + rotasi otomatis.
- `docker-compose.yml` — contoh pakai.

## Cara pakai

```bash
docker compose up -d --build
```

Env var yang **sama seperti biasa** kamu pakai untuk image jacobalberty
(`ISC_PASSWORD`, `FIREBIRD_DATABASE`, `FIREBIRD_USER`, `TZ`, dst) tetap
berlaku semua, tidak berubah. Yang baru cuma 3 ini:

| Variable | Default | Keterangan |
|---|---|---|
| `BACKUP_CRON` | `0 2 * * *` | Jadwal cron backup. |
| `BACKUP_RETENTION_DAYS` | `7` | Backup lebih tua dari sekian hari otomatis dihapus. |
| `BACKUP_DATABASES` | (kosong = auto) | Nama file `.fdb` yang di-backup, pisah koma. Kosong = semua `*.fdb` di `/firebird/data`. |

## Volume

Tetap satu volume `/firebird` seperti image aslinya — backup otomatis
ditaruh di subfolder baru `/firebird/backups`, tidak perlu volume tambahan.

## Backup manual / cek status

```bash
docker exec firebird25 /usr/local/bin/backup.sh
docker exec firebird25 tail -f /var/log/firebird-backup.log
```

## Restore

Sama seperti biasa pakai `gbak -c`, atau taruh file `.fbk` (bukan `.gz`) di
`/firebird/restore` — fitur auto-restore bawaan image jacobalberty akan
otomatis restore ke `/firebird/data` saat container start (kalau `.fdb` yang
sepadan belum ada):

```bash
# dari luar container: unzip dulu hasil backup
gunzip -k mydb_20260819_020000.fbk.gz

docker cp mydb_20260819_020000.fbk firebird25:/firebird/restore/
docker restart firebird25
```

Atau restore manual ke nama file lain tanpa restart:

```bash
docker exec -it firebird25 bash
source /firebird/etc/SYSDBA.password
gbak -c -user "$ISC_USER" -password "$ISC_PASSWORD" \
  /firebird/backups/mydb_20260819_020000.fbk \
  /firebird/data/mydb_restored.fdb
```

## Catatan

- Backup pakai `gbak -b` (logical backup) — aman dijalankan sambil server
  tetap online, tidak perlu shutdown/lock database.
- Kalau nanti butuh backup incremental (`nbackup`) untuk database besar,
  tinggal bilang, saya buatkan variannya.
- Pastikan volume `/firebird` (termasuk subfolder `backups`) ikut di-backup
  di level infrastruktur juga (snapshot VPS dll) — ini melindungi dari
  corruption database, bukan dari hilangnya seluruh volume/disk.
