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

**Subnet router on a separate box.** The homelab box advertises the home LAN (`192.168.1.0/24`) to the tailnet. That lets me reach devices that can't run Tailscale, like the PowerEdge's iDRAC (remote management card). I put the subnet router on the homelab box instead of a VM on the PowerEdge on purpose: if the PowerEdge is down, I still need a way in to fix it.

**HTTPS with a real certificate.** Caddy runs on the homelab box as a reverse proxy. It gets a wildcard certificate (`*.home.<domain>`) from Let's Encrypt with a DNS-01 challenge through Cloudflare. The Cloudflare API token is scoped to DNS edit on that one zone only. Public DNS points the wildcard at a Tailscale IP, so the names resolve anywhere, but only tailnet devices can connect.

## Deliberate exceptions

| What | Why | How it's limited |
|---|---|---|
| Album art for Discord | Discord's servers have to fetch the image from the internet | Cloudflare Tunnel (outbound-only connection, no open port) to one hostname |
| Game server VM | Friends without Tailscale need to join | Kept off the tailnet and on its own VM, so it's isolated from everything else |

## Things I checked during an exposure audit

- `ss -tlnp` on every host to see what's listening and on which address
- Router NAT/port forwarding table: empty
- IP passthrough: off
- No UPnP on this gateway model
