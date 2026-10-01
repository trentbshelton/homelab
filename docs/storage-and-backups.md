# Storage and backups

## Storage

| Machine | Drives |
|---|---|
| PowerEdge | 4 × 300 GB SAS on a PERC H710P hardware RAID controller, presented to Proxmox as one ~558 GB volume (LVM) |
| homelab | 240 GB SSD (OS), 4 TB HDD (`/srv/data`), 2 TB HDD (`/srv/backup`) |

The homelab box doesn't use RAID. Its protection is the separate backup drive instead: if the data drive dies, the nightly snapshots are on a different physical disk.

The PowerEdge doesn't have room for the large data, so that stays on the homelab box's drives and is shared over **NFS**:

| Export | Used for | Access |
|---|---|---|
| `/srv/data` | Media, music, Nextcloud user files | read/write, docker VM only |
| `/srv/backup` | Backup snapshots | read/write, docker VM only, `all_squash` to uid 1000 |

The docker VM mounts both in `/etc/fstab` with `_netdev`, so they wait for the network at boot.

When I moved the apps to the PowerEdge, I left the data where it was. The containers just point at the NFS mount. Nextcloud's 268 GB of user files never had to be copied.

## Backups

Two nightly jobs, one per host, each run by a **systemd timer**.

| Host | What it backs up | Method |
|---|---|---|
| homelab | Jellyfin and Caddy config, Nextcloud user files | stop → rsync → start |
| docker VM | Nextcloud database, Nextcloud config, Vaultwarden, ntfy, Uptime Kuma | `mariadb-dump --single-transaction` (no downtime), stop → rsync → start for the SQLite apps |

How the scripts work:

1. Stop the containers that use SQLite, so the copy is consistent.
2. `rsync --link-dest` into a new dated folder. Unchanged files are hard links to the previous snapshot, so 14 days of history takes very little space.
3. Verify the copy with a dry-run rsync, **then** restart the containers. Restarting first makes SQLite touch its own files, and the verify step fails even though the copy was fine.
4. Write a manifest and send a heartbeat to Uptime Kuma.
5. Delete snapshots older than 14 days.

If the script fails, systemd's `OnFailure=` sends a push notification. If it never runs at all, Uptime Kuma notices the missing heartbeat after 26 hours and alerts.

See [write-up #1](../writeups/01-silent-backup-failure.md) for how I found out these backups had been broken.
