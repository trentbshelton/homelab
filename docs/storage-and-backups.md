# Storage and backups

## Storage

| Machine | Drives |
|---|---|
| PowerEdge | 4 × 300 GB SAS in **RAID 10** on a PERC H710P hardware RAID controller, presented to Proxmox as one ~558 GB volume (LVM) |
| T320 (TrueNAS SCALE) | 256 GB SSD (OS), and three ZFS pools below |

RAID 10 mirrors pairs of drives and stripes across the pairs. It can lose one drive from each mirror and keep running, and it's faster than RAID 5/6 because it doesn't calculate parity. The tradeoff is that only half the raw space is usable (1.2 TB raw → ~558 GB).

The PowerEdge doesn't have room for the large data, so that lives on the T320 and is shared over **NFS**. The [build log](t320-nas.md) covers how it was set up and how the data moved over.

| Pool | Drives | Job |
|---|---|---|
| `data` | 8 TB + 8 TB **mirror** | Media, music, downloads, Nextcloud user files |
| `replica` | 4 TB | Nightly copy of `data`, 30 days of history |
| `backup` | 2 TB (SMR) | Nightly app backups |

| NFS share | Used for | Access |
|---|---|---|
| `/mnt/data` (+ `nextcloud-data`, `backups` child datasets) | Everything the apps read and write | read/write, docker VM only |
| `/mnt/backup/nightly` | Backup snapshots | read/write, docker VM only |

The docker VM mounts them in `/etc/fstab` with `_netdev`, so they wait for the network at boot. The mount paths (`/mnt/nas/...`) stayed the same when the data moved from the old homelab box to the T320, so no app config had to change.

`media/` and `downloads/` are plain folders in the `data` root, not separate datasets. Files in `media/` are hard links into `downloads/`, and hard links can't cross ZFS datasets.

## Backups

| What | How | Where it goes |
|---|---|---|
| App data on the docker VM: Nextcloud database and config, Vaultwarden, Uptime Kuma | Nightly script on a **systemd timer**. `mariadb-dump --single-transaction` (no downtime), stop → rsync → start for the SQLite apps | `backup` pool |
| Everything on the `data` pool (Nextcloud user files, music, media) | ZFS snapshots every night at 3:30 (kept 14 days), then **local ZFS replication** of each snapshot | `replica` pool, kept 30 days |

The `data` mirror keeps running if a drive dies, but a mirror isn't a backup: a deleted or corrupted file is gone from both drives at once. The snapshots on `replica` are what cover that. The old homelab box had its own nightly script for Jellyfin and Caddy; it was retired with the box (Oct 2026).

How the app backup script works:

1. Stop the containers that use SQLite, so the copy is consistent.
2. `rsync --link-dest` into a new dated folder. Unchanged files are hard links to the previous snapshot, so 14 days of history takes very little space.
3. Verify the copy with a dry-run rsync, **then** restart the containers. Restarting first makes SQLite touch its own files, and the verify step fails even though the copy was fine.
4. Write a manifest and send a heartbeat to Uptime Kuma.
5. Delete snapshots older than 14 days.

If the script fails, systemd's `OnFailure=` sends a push notification. If it never runs at all, Uptime Kuma notices the missing heartbeat after 26 hours and alerts.

See [write-up #1](../writeups/01-silent-backup-failure.md) for how I found out these backups had been broken.
