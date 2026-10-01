# Monitoring and alerts

## Uptime Kuma

One Uptime Kuma instance watches every user-facing service: Nextcloud, Vaultwarden, Navidrome, Jellyfin, the calendar, the reverse proxy, Proxmox, Portainer, and the dashboards.

- HTTP(S) checks go through the real domain names, so a check fails if any part of the path breaks (DNS, Caddy, certificate, or the app itself).
- Backup jobs use **push** monitors. The job pings Kuma when it finishes, and Kuma alerts when the pings stop.

Lesson learned: on a push monitor, the interval means "how long silence is allowed," not how often to check. I first copied `60` seconds from another monitor, and it flagged a perfectly healthy daily backup as down a minute later. It's now 26 hours.

## ntfy

ntfy sends push notifications to my phone. These all post to it:

- Uptime Kuma (service down / back up)
- systemd `OnFailure=` units (any failed backup or script)
- Host boot and shutdown messages
- The UPS (on battery, low battery, back on power)

## Keeping it accurate

Monitoring is only useful if it matches what's actually running. After I removed some services, I cleaned out 10 monitors that were permanently "down" and had trained me to ignore the alerts. When I add a new container, I add a monitor for it the same day.
