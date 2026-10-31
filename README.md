# homelab

My home server setup. I use it to self-host the services my friends and I use every day, and to practice the same skills used in IT support and networking.

This repo documents how it's built, how it's secured, and the problems I've run into and fixed.

## Hardware

| Machine | Role |
|---|---|
| Dell PowerEdge (Xeon E5-2620, 12 threads) | Proxmox VE hypervisor. 4 × 300 GB SAS drives in RAID 10 on a PERC H710P hardware RAID controller |
| Dell PowerEdge T320 (Xeon E5-2430L v2) | NAS running TrueNAS SCALE. ZFS mirror of 2 × 8 TB for data, a 4 TB pool with a nightly copy of it, and a 2 TB pool for app backups. See the [build log](docs/t320-nas.md) |
| CyberPower CP1500 UPS | Battery backup for the servers and the switch. Monitored with NUT |
| AT&T gateway → Cisco switch | Home network |

## Layout

```
                         Internet
                            │
                     AT&T gateway  (no port forwards)
                            │
                     Cisco switch
            ┌───────────────┴────────────────┐
            │                                │
   Dell PowerEdge (Proxmox)            Dell T320 (TrueNAS SCALE)
     ├─ VM: docker                       ├─ data: 8 TB mirror (NFS)
     │    ├─ all apps                    ├─ replica: nightly copy of data
     │    ├─ Caddy reverse proxy (HTTPS) └─ backup: app backups
     │    └─ Tailscale subnet router
     ├─ VM: game servers
     └─ LXC: tools
```

Everything is reached over **Tailscale** (a WireGuard VPN). Nothing on the home network is port-forwarded to the internet.

## Services

All apps run in Docker on the `docker` VM, one folder and one compose file per service. Their large data lives on the T320 over NFS.

| Service | What it does |
|---|---|
| Nextcloud (+ MariaDB, Redis) | File storage and sharing for 4 users |
| Vaultwarden | Password manager (Bitwarden-compatible) |
| Navidrome | Music streaming |
| Jellyfin | Movies and TV. Offline while it moves to an OptiPlex 3040 for Intel Quick Sync |
| Baikal + AgenDAV | Self-hosted calendar that syncs to my phone (CalDAV) |
| Wallos | Tracks subscriptions and sends renewal reminders |
| Uptime Kuma | Monitors every service and sends alerts |
| Custom dashboard | Status page I built (Node.js) |

## Docs

- [Network and remote access](docs/network.md)
- [Storage and backups](docs/storage-and-backups.md)
- [Monitoring and alerts](docs/monitoring.md)
- [Power protection (UPS)](docs/power.md)
- [T320 NAS build log](docs/t320-nas.md)

## Config

- [services/](services/): the compose file for each service
- [scripts/backup-appdata-docker-vm.sh](scripts/backup-appdata-docker-vm.sh): the nightly backup script

## Write-ups

Real problems from this lab, written as Problem → Troubleshooting → Fix → What I learned.

1. [My nightly backup failed and nothing told me](writeups/01-silent-backup-failure.md) (Sept 2026)

Secrets, real IP addresses, and domain names are removed from everything in this repo.
