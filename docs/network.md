# Network and remote access

## Goal

Reach every service from anywhere without exposing anything to the internet.

## How it works

**Tailscale for all access.** Every server and my own devices are on one Tailscale network (tailnet). Services are only reachable through it. The router has zero port forwards.

**Services bind to the Tailscale IP, not `0.0.0.0`.** In each compose file, ports are published like this:

```yaml
ports:
  - "<tailscale-ip>:8081:80"
```

That way a service can't be reached from the home LAN or any other interface by accident. During an audit I found four containers published on `0.0.0.0` and fixed them.

**Subnet router.** One machine advertises the home LAN (`192.168.1.0/24`) to the tailnet. That lets me reach devices that can't run Tailscale, like the iDRACs (remote management cards) and the TrueNAS web UI.

This used to run on the old homelab box, on purpose: it was separate from the PowerEdge, so if the PowerEdge went down I still had a way in to fix it. When I retired that box (Oct 2026), the route moved to the Docker VM. That works, but the Docker VM runs on the PowerEdge, so a dead PowerEdge also takes out remote access to its own iDRAC. The plan is to move the route to the OptiPlex 3040 once it's set up.

**HTTPS with a real certificate.** Caddy runs on the Docker VM as a reverse proxy ([config](../services/caddy/)). It used to run on the old homelab box, and turning that box off took every site down with it, so it now lives next to the apps. It gets a wildcard certificate (`*.home.<domain>`) from Let's Encrypt with a DNS-01 challenge through Cloudflare. The Cloudflare API token is scoped to DNS edit on that one zone only. Public DNS points the wildcard at a Tailscale IP, so the names resolve anywhere, but only tailnet devices can connect.

## Deliberate exceptions

| What | Why | How it's limited |
|---|---|---|
| Album art for Discord | Discord's servers have to fetch the image from the internet | Cloudflare Tunnel (outbound-only connection, no open port) to one hostname. `cloudflared` runs on the Docker VM and hands traffic to Caddy on `127.0.0.1` ([config](../services/cloudflared/)) |
| Game server VM | Friends without Tailscale need to join | Kept off the tailnet and on its own VM, so it's isolated from everything else |

## Things I checked during an exposure audit

- `ss -tlnp` on every host to see what's listening and on which address
- Router NAT/port forwarding table: empty
- IP passthrough: off
- No UPnP on this gateway model
