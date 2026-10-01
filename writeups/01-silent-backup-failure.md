# My nightly backup failed and nothing told me

**When:** September 13–14, 2026, right after I moved most of my apps from the homelab box to a new Proxmox VM.

## Problem

The day after the move, I was looking at my dashboard and wondered what the "nightly backup" actually covered. When I checked, that night's backup on the homelab box had **failed**, and I had gotten no alert at all.

## Troubleshooting

**1. Check the job itself.**

```
systemctl status appdata-backup.service
journalctl -u appdata-backup.service
```

The 3 AM run on Sept 13 crashed in the first second with `no such service: sonarr`. Every run for weeks before that had succeeded.

The script stops a hardcoded list of containers before copying their data. I had removed some of those services and moved others to the PowerEdge, but never updated the list. The script uses `set -euo pipefail`, so the first missing container killed the whole run.

**2. Why no alert?**

The failure alert and the Uptime Kuma heartbeat both found ntfy and Uptime Kuma with `docker inspect` on the **local** Docker network. Those containers had moved to the docker VM, so the lookup returned nothing and the alerts went nowhere.

That meant it wasn't only the backup. Since the move, **no** failure alert from that host could reach my phone.

**3. What was actually covered?**

The backup only covered data on the homelab box. Everything that had just moved to the docker VM had **no backup at all**, including Vaultwarden (passwords) and the Nextcloud database. Even if the script hadn't crashed, the most important data was no longer being backed up.

## Fix

1. **homelab script:** trimmed the container list to the two services still on that box (Jellyfin, Caddy).
2. **Alert scripts:** pointed them at ntfy and Uptime Kuma on the docker VM by IP and **published** port. A container's internal port isn't reachable from another host.
3. **New backup on the docker VM** for everything that had none:
   - Nextcloud database with `mariadb-dump --single-transaction` (no downtime)
   - Vaultwarden, ntfy, Uptime Kuma: stop → rsync → verify → start
   - systemd timer scheduled after the homelab job, with `OnFailure=` alerts
4. **Writing to the NFS backup share** took four fixes in a row:
   - The export was read-only, and so was the client's `/etc/fstab` mount option. Both had to change.
   - `root_squash` turned root's writes into `nobody`. I scoped the export to `all_squash,anonuid=1000`.
   - `rsync -a` tried to `chown` every file, which squashing doesn't allow. I switched to `-rlptD --no-owner --no-group`.
   - With the `sync` export option, ~27,000 small files took about 1 per second. I switched the backup-only export to `async`.
5. **Push monitor:** added a heartbeat monitor in Uptime Kuma, so a job that never runs also triggers an alert after 26 hours.

**Result (Sept 14):** the first full run copied 26,921 files (850 MB), passed verification, and sent its heartbeat. Both backup monitors are green.

## What I learned

- **No alerts doesn't mean nothing is wrong.** My alerting broke the same way the backup did. I only caught this within a day because I happened to look.
- **A migration isn't done when the apps start.** Backups, alerts, and monitoring all have to move with them, and that's what I had forgotten.
- **Hardcoded lists rot.** When I move or remove a service, I need to update every script that names it. Newer scripts (like the UPS shutdown) look things up when they run instead.
- **Check what a backup covers, not just whether it ran.** Even without the crash, it would have kept running every night while missing my passwords and the Nextcloud database.
- **Work through one layer at a time.** The NFS write problem was four separate issues stacked on top of each other: export, mount, squash, then rsync flags.
