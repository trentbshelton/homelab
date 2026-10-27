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
cycled remotely.

## Step 2: Flash the H310 to IT mode

TODO

## Step 3: Boot SSD and TrueNAS install

TODO

## Step 4: Drives and pool

TODO

## Step 5: Moving the data over

TODO

## Step 6: Switching services over and retiring the old box

TODO

## What I learned

TODO
