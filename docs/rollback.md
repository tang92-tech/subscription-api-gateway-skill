# Backup and rollback

## Create a snapshot

```bash
sudo ./scripts/backup.sh
```

The script stops neither service nor database writes; for a strict SQLite snapshot, briefly stop New API after notifying users, then run the backup and restart it.

## Restore

```bash
sudo ./scripts/rollback.sh /opt/subscription-api-gateway/backups/<timestamp>.tar.gz
```

Rollback:

1. validates that the archive is under the deployment backup directory;
2. creates a pre-rollback safety snapshot;
3. stops the compose project;
4. restores `.env`, `data`, compose, and version lock;
5. starts services and runs a local smoke test.

If any step fails, leave services stopped rather than serving a half-restored state. Inspect and restore the pre-rollback snapshot manually.
