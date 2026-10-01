# Power protection (UPS)

A CyberPower CP1500 UPS powers the PowerEdge and is connected to it over USB.

## Setup

- **NUT** (Network UPS Tools) runs on the Proxmox host in standalone mode with the `usbhid-ups` driver.
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
