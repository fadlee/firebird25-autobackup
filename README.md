# Auto-backup wrapper for jacobalberty/firebird:v2.5.9-ss

This is **not** a new Firebird image — it just layers cron + `gbak` backups on
top of the `jacobalberty/firebird:v2.5.9-ss` image you already use. All the
original image's behavior (SYSDBA setup, auto-create database, auto-restore
from `/firebird/restore`, etc.) works exactly as before — the original
entrypoint is untouched, only wrapped.

## Contents

- `Dockerfile` — `FROM jacobalberty/firebird:v2.5.9-ss`, adds `cron` + `gzip`.
- `docker-entrypoint-wrapper.sh` — installs the cron schedule first, then
  `exec`s into `/usr/local/firebird/docker-entrypoint.sh` (the image's
  original entrypoint).
- `backup.sh` — runs `gbak -b` (logical/hot backup) using the same SYSDBA
  credentials the original image generates/sets
  (`/firebird/etc/SYSDBA.password`), gzips the output, rotates old backups.
- `docker-compose.yml` — usage example.

## Usage

```bash
docker compose up -d --build
```

All the env vars you normally use with the jacobalberty image
(`ISC_PASSWORD`, `FIREBIRD_DATABASE`, `FIREBIRD_USER`, `TZ`, etc.) keep
working unchanged. Only these 3 are new:

| Variable | Default | Description |
|---|---|---|
| `BACKUP_CRON` | `0 2 * * *` | Cron schedule for backups. |
| `BACKUP_RETENTION_DAYS` | `7` | Backups older than this many days are deleted automatically. |
| `BACKUP_DATABASES` | (empty = auto) | Comma-separated `.fdb` files to back up. Empty = all `*.fdb` in `/firebird/data`. |
| `BACKUP_USER` | `SYSDBA` | Firebird user used by `gbak`. |
| `BACKUP_ROLE` | `RDB$ADMIN` | Firebird role passed to `gbak`; grant it to `BACKUP_USER` on each database. |
| `BACKUP_PASSWORD` | (empty = auto) | Password for `BACKUP_USER`. Empty = use `ISC_PASSWD`/`ISC_PASSWORD` from `/firebird/etc/SYSDBA.password`. |

### Grant backup role with `isql`

`BACKUP_USER` must have the `RDB$ADMIN` role on every database being backed up.
This is a SQL grant stored in the target `.fdb`/`.BJDB` database, so use the
Firebird `isql` binary—not `gsec`—to grant it. Run this once per database using
`SYSDBA` or the database owner.

For Docker Swarm, first find the running container:

```bash
CID=$(docker ps -q \
  --filter label=com.docker.swarm.service.name=dev_firebird \
  | head -1)
echo "$CID"
```

Open a shell and load the generated SYSDBA credentials:

```bash
docker exec -it "$CID" bash
source /firebird/etc/SYSDBA.password
/usr/local/firebird/bin/isql \
  /firebird/data/mydb.BJDB \
  -user "$ISC_USER" \
  -password "$ISC_PASSWD"
```

At the `SQL>` prompt, grant the role and commit it:

```sql
GRANT RDB$ADMIN TO <backup-user>;
COMMIT;
QUIT;
```

Replace `mydb.BJDB` and `<backup-user>` with the actual values. If
`SYSDBA.password` contains an old password, replace `$ISC_USER` and
`$ISC_PASSWD` with known-valid SYSDBA credentials. Verify the grant by running
`SHOW GRANTS;` in `isql` before `QUIT`. On Firebird 2.5, if `SHOW GRANTS`
is not supported by the client, the successful `GRANT` followed by `COMMIT` is
sufficient.

Set `BACKUP_USER` and its password securely through your deployment environment
or secret manager (do not commit the password to this repository):

```env
BACKUP_USER=<backup-user>
BACKUP_PASSWORD=<backup-password>
BACKUP_ROLE=RDB$ADMIN
BACKUP_DATABASES=mydb.fdb
```

The role grant is stored in the target database file, not in `security2.fdb`.
`security2.fdb` stores the user and password. `RDB$ADMIN` is an administrative
role, so a dedicated backup user is recommended instead of an application user.

## Volume

Still a single `/firebird` volume, like the original image — backups go into
the new `/firebird/backups` subfolder, no extra volume needed.

## Manual backup / check status

```bash
docker exec firebird25 /usr/local/bin/backup.sh
docker exec firebird25 tail -f /var/log/firebird-backup.log
```

## Restore

Same as usual with `gbak -c`, or drop a `.fbk` file (not `.gz`) into
`/firebird/restore` — the jacobalberty image's built-in auto-restore will
restore it into `/firebird/data` on container start (if the matching `.fdb`
doesn't exist yet):

```bash
# from outside the container: unzip the backup first
gunzip -k mydb_20260819_020000.fbk.gz

docker cp mydb_20260819_020000.fbk firebird25:/firebird/restore/
docker restart firebird25
```

Or restore manually to a different file name without restarting:

```bash
docker exec -it firebird25 bash
source /firebird/etc/SYSDBA.password
gbak -c -user "$ISC_USER" -password "$ISC_PASSWORD" \
  /firebird/backups/mydb_20260819_020000.fbk \
  /firebird/data/mydb_restored.fdb
```

## Notes

- Backup uses `gbak -b` (logical backup) — safe to run while the server is
  online, no shutdown or database lock needed.
- If you later need incremental backup (`nbackup`) for large databases, just
  ask and I'll add a variant.
- Make sure the `/firebird` volume (including the `backups` subfolder) is also
  backed up at the infrastructure level (VPS snapshots, etc.) — this protects
  against database corruption, not against losing the whole volume/disk.
