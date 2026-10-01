# Power protection (UPS)

A CyberPower CP1500 UPS powers both servers: the PowerEdge and the homelab box. Its USB cable goes to the PowerEdge, and the PowerEdge shares the battery status with homelab over the network.

## Setup

- **NUT** (Network UPS Tools) runs on the Proxmox host as a **netserver** with the `usbhid-ups` driver. It listens on localhost and the LAN IP only.
- The PowerEdge's `upsmon` is the **primary**. The homelab box runs `nut-client` as a **secondary**, with its own NUT user.
- On critically low battery, the primary signals a forced shutdown (FSD). Homelab shuts itself down, and the PowerEdge waits for it to disconnect before shutting down its VMs and then itself.
- `upsmon` watches the battery and runs two scripts:

| Script | When | What it does |
|---|---|---|
| `ups-notify.sh` | On battery, low battery, back on power, communication lost | Sends a push notification, more urgent for worse events |
| `ups-shutdown.sh` | Battery critically low | Gracefully shuts down every VM, force-stops any VM that hangs past 60 s, then shuts down the host |

The shutdown script reads the VM list with `qm list` when it runs instead of using a hardcoded list. That way it doesn't break when I add or remove VMs.

## Testing

I tested it by unplugging the UPS. The "on battery" alert never arrived.

The log showed `Permission denied` on the notify script. `upsmon` runs shutdown as root but drops to the `nut` user for normal notifications. My script and token file were root-only, so the alert failed silently.

Fix: `root:nut` ownership, `750` on the scripts, `640` on the token file. I verified with `runuser -u nut -- ups-notify.sh` and then a second real unplug test, which sent the alert.

## Adding the homelab box (Oct 2026)

At first only the PowerEdge was set up to shut down. The homelab box was on the same battery, but nothing told it the battery was low, so it would have lost power hard when the battery ran out. I switched NUT from `standalone` to `netserver` mode and added homelab as a secondary. I checked that the PowerEdge lists both machines as connected clients (`upsc -c`).
