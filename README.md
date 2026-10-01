# homelab

My home server setup. I use it to self-host the services my friends and I use every day, and to practice the same skills used in IT support and networking.

This repo documents how it's built, how it's secured, and the problems I've run into and fixed.

## Hardware

| Machine | Role |
|---|---|
| Dell PowerEdge (Xeon E5-2620, 12 threads) | Proxmox VE hypervisor. 4 × 300 GB SAS drives on a PERC H710P hardware RAID controller |
| Small Debian box ("homelab") | NAS (NFS), reverse proxy, Jellyfin (uses the Intel iGPU for hardware transcoding). SSD boot drive, 4 TB data drive, separate 2 TB backup drive |
| CyberPower CP1500 UPS | Battery backup for both servers. Monitored with NUT |
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
   Dell PowerEdge (Proxmox)            homelab (Debian)
     ├─ VM: docker  ── all apps          ├─ NFS shares (data, backups)
     ├─ VM: game servers                 ├─ Caddy reverse proxy (HTTPS)
     └─ LXC: tools                       ├─ Jellyfin
                                         └─ Tailscale subnet router
```

Everything is reached over **Tailscale** (a WireGuard VPN). Nothing on the home network is port-forwarded to the internet.

## Services

All apps run in Docker on the `docker` VM, one folder and one compose file per service.

| Service | What it does |
|---|---|
| Nextcloud (+ MariaDB, Redis) | File storage and sharing for 4 users |
| Vaultwarden | Password manager (Bitwarden-compatible) |
| Navidrome | Music streaming |
| Jellyfin | Movies and TV (runs on the homelab box for the iGPU) |
| Baikal + AgenDAV | Self-hosted calendar that syncs to my phone (CalDAV) |
| Wallos | Tracks subscriptions and sends renewal reminders |
| Uptime Kuma | Monitors every service and sends alerts |
| ntfy | Push notifications to my phone |
| Portainer | Docker management UI |
| Custom dashboard | Status page I built (Node.js) |
| Network map | Live topology diagram I built (Node.js) |

## Docs

- [Network and remote access](docs/network.md)
- [Storage and backups](docs/storage-and-backups.md)
- [Monitoring and alerts](docs/monitoring.md)
- [Power protection (UPS)](docs/power.md)

## Config

- [services/](services/): the compose file for each service
- [scripts/backup-appdata-docker-vm.sh](scripts/backup-appdata-docker-vm.sh): the nightly backup script

## Write-ups

Real problems from this lab, written as Problem → Troubleshooting → Fix → What I learned.

1. [My nightly backup failed and nothing told me](writeups/01-silent-backup-failure.md) (Sept 2026)

Secrets, real IP addresses, and domain names are removed from everything in this repo.
