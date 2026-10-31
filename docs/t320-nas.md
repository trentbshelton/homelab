# T320 NAS build

Build log for replacing the old homelab box with a Dell PowerEdge T320
running TrueNAS SCALE. Written as I go, so later steps fill in over time.

## Why

The old NAS (a desktop running Debian with two data drives) hangs during
POST on every reboot and needs someone to press the reset button by hand.
It also only has room for two data drives. The plan is to split its jobs:

- T320: storage only (TrueNAS SCALE, ZFS, NFS shares for the Docker VM)
- OptiPlex 3040: Jellyfin with Intel Quick Sync, plus the reverse proxy
- Old homelab box: retired once everything is moved

## The hardware

Bought used from a local computer store for $99 (final sale, no drives).

![T320 at the store](images/t320/01-store.jpg)

- Dell PowerEdge T320 tower
- Intel Xeon E5-2430L v2, 6 cores / 12 threads, 60W
- 16GB DDR3-1600 ECC
- 2x Broadcom BCM5720 gigabit NICs
- PERC H310 Adapter (PCIe, slot 6)
- Hot-swap 3.5" backplane, came with only 2 drive caddies
- iDRAC7 for remote power control and console

I picked a tower over another rack server because it lives in my bedroom,
and the low-power "L" CPU keeps idle draw low for a box that runs 24/7.

## Step 1: First power-on

No drives yet. The goal was to confirm the hardware and find out which
storage controller it has, since that decides whether ZFS can see the disks
directly.

![First POST](images/t320/02-first-post.jpg)

POST showed the CPU and all 16GB of memory. The onboard SATA is in AHCI mode
with the DVD drive on port E, which is the spare port the boot SSD will use.
It also said "Lifecycle Controller update required". That only affects
Dell's built-in update/OS tool, so I left it for later.

Device Settings in System Setup (F2) showed the storage controller:

![Device Settings showing the PERC H310](images/t320/03-device-settings-h310.jpg)

A PERC H310 is a RAID card. ZFS wants raw access to every disk (no RAID
layer in between) so it can handle redundancy and read SMART data itself.
The H310 can be crossflashed to LSI 9211-8i firmware in IT mode, which
turns it into a plain HBA. That is the next step, done before any drives
go in.

iDRAC is set to a static address on the LAN so the server can be power
cycled remotely. The firmware on it is very old:

![iDRAC firmware 1.57.57](images/t320/04-idrac-firmware-1.57.jpg)

That version only speaks TLS 1.0, so no modern browser will open its web
UI. I planned to update it, but then found out it wouldn't help: logging in
over SSH printed `License Violation: "SSH"`. This one only has the iDRAC7
Basic license, so there's no web UI or SSH at any firmware version, just
IPMI. IPMI over LAN didn't work at first because the
"Enable IPMI Over LAN" change never got saved. You have to leave System
Setup through Finish and say Yes to saving. After that, `ipmitool` could
power cycle it and read temps and fans.

## Step 2: Flash the H310 to IT mode

I followed Fohdeesha's PERC crossflashing guide (H310 Full Size section).
The guide ships two live images, FreeDOS and Debian. I put both on one USB
stick with Ventoy.

Prep, per the guide:
- Disabled Virtualization Technology, SR-IOV and I/OAT DMA in the BIOS
- Kept boot mode on BIOS, not UEFI
- No drives connected to the card

In FreeDOS, `info` confirmed a PERC H310 Adapter, chip revision B2. I wrote
down the card's SAS address there, because the flash wipes it. Then
`310FLCRS` erased the Dell firmware (twice, to be sure) and wrote the IT
mode SBR:

![310FLCRS finishing with no errors](images/t320/06-h310-310flcrs-success.jpg)

Next I booted the Debian image. It has SSH, so I ran the rest from another
machine. The `H310` script boots the card from RAM, then flashes LSI's
9211-8i IT firmware (20.00.07.00) to the card's flash and verifies it.
After one reboot, `setsas` put the original SAS address back, and `info`
then showed:

```
Firmware Product ID : 0x2213 (IT)
Firmware Version    : 20.00.07.00
Board Name          : SAS9211-8i
BIOS Version        : N/A
```

I skipped the boot ROM. Nothing boots from this card, since the boot SSD
goes on the onboard SATA port, and without the ROM the card adds no time
to POST.

Annoyances:
- The F11 boot menu froze the first time after a cold boot. Setting a
  one-time boot with `ipmitool chassis bootdev disk` and resetting was
  more reliable.
- After a warm reboot the BIOS often didn't see the USB stick at all.
  A full power off and on through IPMI fixed it every time.

## Step 3: Boot SSD and TrueNAS install

The boot drive is a spare Samsung PM851 256GB SSD. It goes on onboard SATA
port E using the DVD drive's data cable and a normal SATA power plug. That
port only links at SATA2 (3Gbps), which doesn't matter for a boot drive.

I added the TrueNAS SCALE 25.10 ISO to the same Ventoy stick from step 2
and checked its SHA256 on the stick.

The SSD still had an old Linux install on it, so the BIOS booted that
instead and landed at a `grub rescue>` prompt. The normal fix is to pick
the USB stick from the F11 boot menu, but the graphical F2/F11 menus kept
freezing (with two different keyboards, so it wasn't the keyboard). The
workaround:

1. Unplugged the SSD's data cable
2. Booted the live Debian image from the stick with
   `ipmitool chassis bootdev disk` and a reset
3. Plugged the SSD back in while it was running (SATA is hot-pluggable)
4. Over SSH, ran `wipefs -a` on it and zeroed the first and last 16MB to
   clear the old partition tables

With nothing bootable on the SSD, a cold boot went straight to the stick
and the TrueNAS installer. I installed to the SSD in legacy BIOS mode and
answered No to "Allow EFI boot", since this box boots BIOS only. The
installer's shutdown hung on "watchdog did not stop", so I reset it through
IPMI. After that it booted TrueNAS on its own.

After first boot:

- Gave it a static IP below the router's DHCP range. I did this through
  the TrueNAS API, which applies network changes with a 60 second rollback
  timer. If you don't check in before the timer runs out (in case the new
  address locked you out), it puts the old settings back.
- Made an API key for scripting. TrueNAS revokes an API key if it is ever
  sent over plain HTTP, so it only gets used over HTTPS.
- Set the time zone.

The only monitor I had free to leave on it is a 1992 Packard Bell CRT. It
only does 640x480 at 60Hz (and 720x400 for text mode) and has no EDID, so
Linux picked a higher mode and the screen showed static. Adding the kernel
option `video=640x480@60` in TrueNAS's advanced settings fixed it, and the
console menu now shows up clearly on the CRT.

## Step 4: Drives and pool

The original plan was to buy no new drives and reuse the two from the old
box:

| Drive | Type | Old role | Used |
|---|---|---|---|
| WD 4TB (WD40EZAX) | CMR | `/srv/data` | 1.3TB |
| Seagate 2TB (ST2000DM008) | SMR | `/srv/backup` | 320GB |

Both passed SMART with 0 reallocated or pending sectors. The 2TB had a
count of UDMA CRC errors, which usually comes from a bad cable, not the
disk.

The problem is that both drives are ext4, and a disk can't join a ZFS pool
without being wiped. The 4TB holds everything, and nothing else in the lab
has 1.3TB free to hold it in the meantime. So the order had to be:

1. Move the 2TB over first and make it a pool
2. Copy the 4TB's data onto it over the network (step 5)
3. Only then wipe the 4TB

The 2TB became a single-disk pool called `backup`. That's its long-term
job (an SMR drive is fine for backups and bad for anything else), so naming
it that now means no rename later. For now it also holds the copy of the
main data.

Then the plan changed: instead of several used 2TB drives, I found a used
WD 8TB (WD80EZAZ, a "white label" drive pulled from an external, CMR and
helium filled) on Facebook Marketplace for $150. Before buying I asked the
seller for SMART data on the exact drive I'd get:

- About 40,900 power-on hours (around 4.7 years), only 59 power cycles
- 0 reallocated, 0 pending, 0 uncorrectable sectors
- Helium level at 100
- The seller had already done a full zero pass, and SMART stayed clean

That's old but healthy. The plan for it:

- 8TB becomes the new main pool
- Once the data is off the old 4TB, attach the 4TB to it as a mirror
  (usable space is the smaller disk, about 3.6TB, until...)
- Later, replace the 4TB with a second 8TB, and the mirror grows to 8TB

The T320 only came with 2 caddies, so I bought a third party 4-pack that
lists the T320 as supported. It fits fine. Some shucked drives won't spin
up in servers because of the 3.3V power disable pin, but this backplane
detected the 8TB right away.

TrueNAS 25.10 removed the button and API for running SMART tests. To run a
long test anyway, I made a disabled cron job in TrueNAS that runs
`smartctl` and trigger it by hand. The long test on 8TB takes 16-18 hours.
The main pool gets built once it passes.

It passed with no errors, and the main pool `data` went onto the 8TB as a
single disk for now.

### A second 8TB instead of the 4TB

Mirroring the 8TB with the old 4TB would have capped the pool at 3.6TB. I
found another seller with a stack of enterprise Toshiba 8TB drives for $120
each, so I bought one to mirror the 8TB properly.

The drive I got wasn't the one in the listing. It was an MG05ACA800E (one
generation older) instead of the MG06 in the photos, with about 71,500
power-on hours (over 8 years). The SMART data was still clean, so I kept
it. It's a mirror, so if this drive dies early the WD keeps everything
running while I replace it.

It passed a long SMART test (about 12 hours at 7200rpm), and then I
attached it to `data` as a mirror. The resilver (ZFS copying everything
onto the new disk) took a little over 2 hours with 0 errors.

| Pool | Drives | Layout | Job |
|---|---|---|---|
| `data` | WD 8TB + Toshiba 8TB | Mirror | Everything (NFS to the Docker VM) |
| `backup` | Seagate 2TB | Single disk | Nightly app backups |

## Step 5: Moving the data over

Before pulling the 2TB out of the old box, I paused everything that wrote
to it: the backup timers on both hosts, the NFS export, and the fstab
lines (commented out, not deleted). The backup history on it got copied to
the 4TB and checked with `diff -rq` first, since the drive was about to be
wiped.

Pulling it broke something. When the old box came back up, every web
service was down. The startup script for the containers waits for all the
data mounts first, and it was still waiting for the 2TB. The containers
showed as "Up" but had no ports. I changed the script to only wait for
mounts that are actually listed (not commented out) in `/etc/fstab`, and
everything came back.

For the copy, I made a dataset `backup/staging`, shared it over NFS to the
old box only, and ran `rsync -aH --numeric-ids` from the old box inside
tmux, so it would survive me disconnecting.

It started at about 1MB/s. Most of the files at the start were small, NFS
writes are synchronous by default (each file waits until it's safely on
disk), and the 2TB is an SMR drive, which is slow at exactly that kind of
write. Setting `sync=disabled` on the dataset brought it to about 20MB/s on
small files and about 195MB/s on big ones. The risk is losing the last few
seconds of writes if the power cuts out, which is fine for a copy I can
just run again, and the server is on a UPS anyway.

All 1.3TB copied without errors in about 6 to 7 hours. A second rsync pass
afterwards found nothing left to transfer.

### While waiting on the main pool

The old box's backup drive is gone now, so the nightly backups had nowhere
to go. Until the main pool is built, they point at the T320 instead:

- A new dataset `backup/nightly`, shared over NFS to both hosts, takes the
  nightly app backups from both
- A nightly rsync keeps `backup/staging` in sync with the old box's data
  drive. The script refuses to run if the source drive isn't mounted or
  looks almost empty, so a failed mount can't make it delete the copy.
- ZFS snapshots of `backup/staging` every day, kept for 7 days

These mounts use NFSv3, because `rsync -A` (copy ACLs) failed over NFSv4.
They also use `x-systemd.automount`, so if the T320 is down the other
machines still boot normally and only the backup job fails.

While testing this I found that the Docker VM's backup had stopped sending
its heartbeat to Uptime Kuma two days earlier. The heartbeat token lived in
a file I had deleted while replacing ntfy with Pushover. The backup itself
was still running fine. I moved the token to the file the other scripts
use.

### Copying onto the main pool

Once `data` existed, the copy from `backup/staging` ran locally on the
T320, with no network involved. I split `data` into child datasets that
matched the old folders (`media`, `downloads`, `nextcloud-data`,
`backups`) so each could have its own snapshot settings.

The first copy finished with rsync exit code 23 ("some files could not be
transferred"). All 1,033 errors were in `media/`. Those files are hard
links into `downloads/`: the same file on disk shows up in both folders,
so a movie takes up space once instead of twice. A hard link can't cross
filesystems, and in ZFS every dataset is its own filesystem, so rsync
couldn't link `media/` to `downloads/` anymore.

I deleted the `media` and `downloads` datasets, made them plain folders in
the `data` root so they share one filesystem again, and copied them again.
The second copy finished cleanly, and a dry-run rsync afterwards found 0
differences. Both sides had the same 1,033 hard links.

## Step 6: Switching services over and retiring the old box

### Cutover

Downtime was about 27 minutes:

1. Stopped the apps that write to the data
2. Ran a final `rsync -aHAX --delete` from the old box to the T320. A dry
   run first showed only what had changed since the copy.
3. Added NFS shares on the T320 for `/mnt/data`, `/mnt/data/nextcloud-data`
   and `/mnt/data/backups`. With NFSv3, each child dataset needs its own
   share, because it's a separate filesystem.
4. Changed `/etc/fstab` on the Docker VM and the old box to mount the T320
   instead of the old box. The old lines are commented out, not deleted.
5. Started everything again and opened real files to check they worked

The apps never noticed. They still use the same paths (`/mnt/nas/data`),
just from a different server.

I added two Uptime Kuma monitors for the T320 (web UI and the NFS port).
TrueNAS has no built-in Pushover alerts, so a small script on the T320
runs every 10 minutes and sends a push if a pool isn't healthy, a SMART
check fails, the reallocated sector count goes up, or a drive gets too hot.

### Turning off the old box broke every website

With the data moved, I shut down the old box to pull its 4TB. Every
`*.home.<domain>` site stopped loading, even though the apps were all
running on the Docker VM.

The reason was the reverse proxy. Caddy still ran on the old box, and the
wildcard DNS record pointed at the old box's Tailscale IP. The apps were
fine, but the only way to reach them by name went through a machine that
was off. The Cloudflare Tunnel for the public album art ran there too.

The original plan was to move Caddy to the OptiPlex along with Jellyfin. I
moved it to the Docker VM instead. Caddy holds no data and only routes
traffic, so it belongs on the machine that's always on.

1. Copied the Caddyfile and Caddy's `/data` folder (certificates and the
   Let's Encrypt account) to the Docker VM, so no certificates had to be
   issued again
2. Built the same Caddy image there (with the Cloudflare DNS plugin) and
   tested every hostname with `curl --resolve` against the new IP while
   the old Caddy was still serving traffic
3. Moved `cloudflared` to the Docker VM. It now hands traffic to Caddy on
   `127.0.0.1` instead of the LAN IP, because the VM's LAN IP comes from
   DHCP.
4. Changed the wildcard DNS record to the Docker VM's Tailscale IP
5. Removed Caddy from the old box's compose file

One thing I missed: Uptime Kuma had `extra_hosts` entries pinning some
hostnames to the old proxy's IP, so a few checks were still going to the
old box. I found it while writing this log and pointed them at the new
proxy.

The DNS record has a 5-minute TTL, so for a few minutes after the change
some devices still had the old IP cached and couldn't load some sites.

### Moving the 4TB over

Before shutting the old box down for good, I saved everything on it that
might matter later to the T320: the compose folder and `.env`, `/etc`,
`/root`, `/home`, `/opt`, crontabs, and all the app data. My first archive
missed `/home`, which had a couple of old admin password files. I noticed
them, so they're in a second archive.

Before wiping the 4TB, I mounted it read-only one last time and compared
it file by file against the T320 with `rsync -n`. All 789,345 files were
on the T320. The only difference was Nextcloud's log file, which had kept
growing on the T320 since the cutover.

I also had to move these off the old box:

- **Tailscale subnet router** (how I reach the iDRACs and the TrueNAS UI
  from outside the house). It's on the Docker VM for now, but that VM runs
  on the PowerEdge, so if the PowerEdge goes down I can't reach its iDRAC
  remotely. It should move to the OptiPlex.
- **Dashboard:** removed the old box from the status service, so it
  doesn't show as down or send an alert

The 4TB went into the T320's fourth bay and became a third pool,
`replica`, with a full copy of `data`:

- Snapshots of `data` (and its child datasets) every night at 3:30, kept
  for 14 days
- A local ZFS replication task copies each new snapshot to `replica`,
  which keeps 30 days

The mirror protects against a dead drive, but it doesn't protect against
deleting something by mistake or files getting corrupted, because those
happen on both drives at once. Snapshots on a separate pool cover that.

| Pool | Drives | Job |
|---|---|---|
| `data` | 8TB + 8TB mirror | All data, shared over NFS |
| `replica` | WD 4TB | Nightly copy of `data`, 30 days of history |
| `backup` | Seagate 2TB | Nightly app backups (databases, configs) |

Jellyfin is off for now. It moves to the OptiPlex 3040 with its saved
config, and the OptiPlex will also run the homelab console on the CRT.

## What I learned

- **Check what a machine does before turning it off, not just what's
  stored on it.** I checked the data drives carefully and forgot that the
  old box was also the reverse proxy, the tunnel and the subnet router.
- **Put stateless routing on the machine that's always on.** Caddy doesn't
  store anything, so putting it on the Docker VM next to the apps means
  one less box that can take every site down.
- **Hard links don't cross ZFS datasets.** Plan datasets around how files
  link to each other, not just around folder names.
- **Verify before wiping, every time.** A dry-run rsync between the old
  drive and the new copy takes a few minutes and proves nothing is
  missing.
- **A mirror isn't a backup.** It covers a dead drive. Snapshots on a
  separate pool cover mistakes.
- **When archiving a machine, take more than the service folders.**
  `/home`, `/opt` and crontabs are small and easy to forget.
