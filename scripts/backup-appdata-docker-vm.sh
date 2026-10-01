#!/usr/bin/env bash
#
# Nightly snapshot of the docker VM's own stateful appdata, pushed across NFS
# to homelab's /srv/backup (mounted here at /mnt/nas/backup). Sibling script
# to homelab's own /srv/compose/scripts/backup-appdata.sh -- same philosophy
# (rsync --link-dest, stop-for-consistency, verify, retention, Kuma
# heartbeat), separate because this VM's appdata never used to exist: it only
# came into being when Nextcloud/Vaultwarden/ntfy/Uptime Kuma moved here
# during the 2026-09 rebuild, and nothing was ever written to back them up.
#
# WHY EACH THING IS HANDLED THE WAY IT IS:
#
#  * Nextcloud's database is dumped with `mariadb-dump --single-transaction`,
#    not stopped-and-file-copied. A logical dump is portable, human-checkable,
#    and needs no downtime -- InnoDB's MVCC gives a consistent snapshot while
#    the app keeps running. This is the exact method already proven for this
#    database during its original migration onto this VM.
#
#  * Vaultwarden, ntfy, and the comprehensive Uptime Kuma all keep state in
#    SQLite. Copying a live SQLite file yields a torn copy that looks fine and
#    restores as corruption -- same reasoning as homelab's Jellyfin backup.
#    All three get stopped together, copied, and restarted together -- they
#    have no startup ordering dependency on each other, unlike Nextcloud/DB/
#    Redis, so there is no reason to do them one at a time.
#
#  * Nextcloud's OWN html/config tree is copied live, not stopped. It is
#    mostly static application files plus config.php; unlike the database it
#    is not being written to continuously, so a live copy is low-risk and a
#    few seconds of Nextcloud downtime for the sake of it is not worth it.
#
#  * The NFS destination (/srv/backup on homelab) squashes every write from
#    this host to uid 1000 -- see /etc/exports on homelab, this
#    export is scoped `all_squash,anonuid=1000,anongid=1000` specifically so
#    this script (which must run as root, same reason as homelab's: it has to
#    read files owned by whatever uid each container runs as) never has to
#    fight root_squash on the way out.
#
#  * The trap is load-bearing. If rsync dies mid-run the containers MUST come
#    back up regardless.
set -euo pipefail

DEST=/mnt/nas/backup/docker-vm-appdata
KEEP=14

STAMP=$(date +%Y-%m-%d_%H%M%S)
TARGET="$DEST/$STAMP"
LATEST="$DEST/latest"

STOPPED=(vaultwarden ntfy uptime-kuma-homelab)
STOPPED_SRC=(/opt/homelab/appdata/vaultwarden /opt/homelab/appdata/ntfy /opt/homelab/appdata/uptime-kuma)

LIVE_NAME=nextcloud-html
LIVE_SRC=/opt/nextcloud/html

# NOT -a: that implies -o -g (preserve owner/group), and the NFS export on
# the receiving end is deliberately `all_squash,anonuid=1000,anongid=1000` --
# every write from this host is forced to uid 1000 no matter who asks,
# root included. rsync then can't chown copied files to match their source
# owner (www-data, mysql, whatever each container runs as) and errors out.
# Dropping owner/group preservation sidesteps this entirely: the backup
# doesn't need to reproduce each container's internal uid, only the file
# content, permission bits, and timestamps.
EXCLUDES=(
  --exclude '*.log'
  --exclude '*.log.*'
  --exclude '*-shm'
  --exclude '*-wal'
)

log() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

started=0
ok=0
cleanup() {
  if [ "$ok" != 1 ] && [ -n "${TARGET:-}" ] && [ -d "$TARGET" ] && [ ! -f "$TARGET/MANIFEST.txt" ]; then
    log "run failed - removing incomplete snapshot $(basename "$TARGET")"
    rm -rf "${TARGET:?}"
  fi
}
restart_containers() {
  if [ "$started" = 1 ]; then
    log "restarting: ${STOPPED[*]}"
    docker start "${STOPPED[@]}" >/dev/null
    started=0
  fi
}
trap 'restart_containers; cleanup' EXIT INT TERM

if [ "$(id -u)" != 0 ]; then
  log "ERROR: must run as root - containers write files owned by their own"
  log "       internal uid (mysql, www-data, etc); an unprivileged rsync"
  log "       would silently skip them."
  exit 1
fi

mkdir -p "$DEST"
LINK=()
[ -d "$LATEST" ] && LINK=(--link-dest="$(readlink -f "$LATEST")")
mkdir -p "$TARGET"

# --- Nextcloud database: logical dump, no downtime --------------------------
log "dumping nextcloud database"
# shellcheck disable=SC1091
[ -f /opt/services/nextcloud/.env ] && { set -a; . /opt/services/nextcloud/.env; set +a; }
if [ -z "${NC_DB_ROOT_PASSWORD:-}" ]; then
  log "ERROR: NC_DB_ROOT_PASSWORD not set - cannot dump the database"
  exit 1
fi
docker exec -e MYSQL_PWD="$NC_DB_ROOT_PASSWORD" nextcloud-db \
  mariadb-dump --single-transaction --routines --triggers -u root nextcloud \
  > "$TARGET/nextcloud-db.sql"
unset NC_DB_ROOT_PASSWORD

# --- Nextcloud html/config, live -------------------------------------------
log "copying $LIVE_NAME (live)"
rsync -rlptDH --no-owner --no-group --delete "${EXCLUDES[@]}" "${LINK[@]}" "$LIVE_SRC/" "$TARGET/$LIVE_NAME/"

# --- SQLite-backed services: stop all, copy all, restart all ----------------
log "stopping: ${STOPPED[*]}"
docker stop "${STOPPED[@]}" >/dev/null
started=1

for i in "${!STOPPED[@]}"; do
  name="${STOPPED[$i]}"
  src="${STOPPED_SRC[$i]}"
  log "copying $name"
  rsync -rlptDH --no-owner --no-group --delete "${EXCLUDES[@]}" "${LINK[@]}" "$src/" "$TARGET/$name/"
done

# Verify BEFORE restarting -- restarting first would let a service touch its
# own SQLite file (WAL checkpoint, journal write) right before the dry-run
# comparison, making a perfectly good copy look like it differs.
log "verifying (dry run, expect 0 transfers)"
for i in "${!STOPPED[@]}"; do
  name="${STOPPED[$i]}"
  src="${STOPPED_SRC[$i]}"
  STATS=$(rsync -rlptDHn --no-owner --no-group --delete "${EXCLUDES[@]}" --info=stats2 "$src/" "$TARGET/$name/")
  XFER=$(printf '%s\n' "$STATS" | grep -oP 'Number of regular files transferred: \K[0-9,]+' | tr -d ,)
  if [ "${XFER:-1}" != "0" ]; then
    log "VERIFY FAILED ($name): $XFER file(s) still differ"
    printf '%s\n' "$STATS"
    exit 1
  fi
done

restart_containers
STATS=$(rsync -rlptDHn --no-owner --no-group --delete "${EXCLUDES[@]}" --info=stats2 "$LIVE_SRC/" "$TARGET/$LIVE_NAME/")
XFER=$(printf '%s\n' "$STATS" | grep -oP 'Number of regular files transferred: \K[0-9,]+' | tr -d ,)
if [ "${XFER:-1}" != "0" ]; then
  log "VERIFY FAILED ($LIVE_NAME): $XFER file(s) still differ"
  printf '%s\n' "$STATS"
  exit 1
fi
log "verify OK: sources and snapshots identical"
ok=1

{
  echo "snapshot:  $STAMP"
  echo "files:     $(find "$TARGET" -type f | wc -l)"
  echo "apparent:  $(du -sh  "$TARGET" | cut -f1)"
  echo "on-disk:   $(du -shl "$TARGET" | cut -f1)   (l = deref hardlinks)"
  echo "verified:  yes"
} > "$TARGET/MANIFEST.txt"
ln -sfn "$STAMP" "$LATEST"

log "pruning, keeping newest $KEEP"
mapfile -t OLD < <(find "$DEST" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r | tail -n +$((KEEP+1)))
for d in "${OLD[@]:-}"; do
  [ -n "$d" ] || continue
  log "  removing $d"
  rm -rf "${DEST:?}/$d"
done

log "done: $TARGET"
du -sh "$DEST" | awk '{print "  docker-vm-appdata backup now: " $1}'

/opt/scripts/kuma-push.sh up "snapshot $STAMP verified" || true
