# Monitoring and alerts

## Uptime Kuma

One Uptime Kuma instance watches every user-facing service: Nextcloud, Vaultwarden, Navidrome, Jellyfin, Soulseek, Wallos, both calendar apps, the game server panel, the reverse proxy, Proxmox, the dashboard and its status service, the public album-cover endpoint Discord uses, and the SSH port of a friend's VM.

- The calendar apps only listen on the VM's loopback, so Kuma joins their Docker network and checks them by container name.

- HTTP(S) checks go through the real domain names, so a check fails if any part of the path breaks (DNS, Caddy, certificate, or the app itself).
- Backup jobs use **push** monitors. The job pings Kuma when it finishes, and Kuma alerts when the pings stop.

Lesson learned: on a push monitor, the interval means "how long silence is allowed," not how often to check. I first copied `60` seconds from another monitor, and it flagged a perfectly healthy daily backup as down a minute later. It's now 26 hours.

## Phone alerts (Pushover)

Every alert reaches my phone through [Pushover](https://pushover.net). Each machine has one small command, [`notify`](../scripts/notify/notify), and everything that wants to alert calls it:

- systemd `OnFailure=` units (any failed backup or script)
- Host boot and shutdown messages, flagging an unclean previous shutdown
- The UPS (on battery, low battery, forced shutdown, back on power)
- The dashboard's status service, when a problem lasts 2+ minutes and again when it clears

Uptime Kuma (service down / back up) and Wallos (subscription renewals) use their built-in Pushover support.

I used to self-host ntfy for this. I replaced it because the notifier ran on the same servers it was watching: if they went down, so did the alerts. Pushover is hosted elsewhere, and with one `notify` command, changing providers again would mean editing one file.

## Keeping it accurate

Monitoring is only useful if it matches what's actually running. After I removed some services, I cleaned out 10 monitors that were permanently "down" and had trained me to ignore the alerts. When I add a new container, I add a monitor for it the same day.
