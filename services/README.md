# services

The real compose files from the `docker` VM. Each service lives in `/opt/services/<name>/` with its own `docker-compose.yml` and `.env`.

Changes made for this repo:

- `${TS_IP}` replaces the VM's Tailscale IP, and `${PROXY_TS_IP}` replaces the reverse proxy's.
- `<tailnet>` replaces my Tailscale network name.
- `.env` files aren't included. Passwords and tokens are only ever referenced as `${VARIABLES}`.

Patterns used throughout:

- Ports are published on the Tailscale IP only (or `127.0.0.1` when `tailscale serve` sits in front), never `0.0.0.0`.
- Image versions are pinned for the important services (Nextcloud, Vaultwarden, MariaDB, Uptime Kuma) so updates happen on purpose.
- Large data lives on the NAS over NFS (`/mnt/nas/...`), and small app data stays on the VM.
