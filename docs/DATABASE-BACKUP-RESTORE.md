# PostgreSQL backup and restore procedure

## Data protection model

- PostgreSQL stores live data in the named Docker volume `postgres_data`.
- A container image, restart policy, or Docker volume is **not** a backup.
- `ops/backup-postgres.sh` writes a PostgreSQL custom-format dump to the host's `backups/` folder, validates its archive listing, calculates SHA-256, and applies the configured retention period.
- `ops/restore-test.sh` restores the selected dump into a new temporary database and drops only that temporary database after verification. It does not overwrite the live database.
- Keep at least one encrypted copy off the application server. A backup on the same disk does not protect against disk/server loss.

## First-time setup

```bash
cp .env.example .env
# Edit .env: use strong, unique passwords; do not commit it.
docker compose up -d postgres
docker compose ps postgres
```

## Take and verify a backup

```bash
./ops/backup-postgres.sh
ls -lh backups/
```

The dump and `.sha256` sidecar must both exist. The restore-test script refuses to proceed without the checksum sidecar. A backup is not considered verified until a restore test succeeds.

## Perform an isolated restore test

```bash
./ops/restore-test.sh
# Or specify a particular dump:
./ops/restore-test.sh backups/ops_lab_YYYYMMDDTHHMMSSZ.dump
```

The script creates a uniquely named temporary database, restores into it, reports the number of restored public tables, and removes the temporary database. If verification fails, retain the dump and logs and investigate; do not delete the source backup.

## Schedule backups

On a Linux host, use a protected systemd timer or root-owned cron entry. Example daily cron at 02:15 UTC:

```cron
15 2 * * * cd /opt/server-operations-lab && ./ops/backup-postgres.sh >> /var/log/server-operations-lab-backup.log 2>&1
```

Ensure the backup user can read `.env`, write the backup directory, and run Docker Compose. Send job failures to the team's agreed alert channel. Test the schedule by running it manually first.

## Production requirements before storing company data

1. Encrypt off-host backup copies and restrict who can read them.
2. Decide RPO (maximum acceptable data loss) and RTO (maximum acceptable recovery time) with the application owner.
3. Keep backups in a separate failure domain from the server.
4. Run scheduled restore tests and record evidence.
5. Monitor backup age, backup size, exit status and restore-test status.
6. Agree on retention and deletion policy before using real customer data.
