#!/bin/bash
# bcache-rollback.sh [bdev ...] — safe teardown in kernel-docs order.
# No args: tears down every registered cache set + backing on this host.
# Cache-loss path included: force-run backing without its cache (writethrough = safe).
set -u
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
if [ $# -gt 0 ]; then DEVS="$@"; else DEVS=$(ls /dev/bcache[0-9]* 2>/dev/null || true); fi
for B in $DEVS; do
  echo "--- stopping $B ---"
  echo 1 > "/sys/block/$(basename $B)/bcache/stop" 2>/dev/null || echo "(already stopped?)"
done
sleep 2
for id in $(ls /sys/fs/bcache/ 2>/dev/null | grep -vE "register|pendings"); do
  echo "--- unregistering cache set $id ---"
  echo 1 > "/sys/fs/bcache/$id/unregister" 2>&1 || echo "(busy or gone)"
done
sleep 2
echo "--- wiping bcache superblocks (backing data otherwise intact at +8K offset per docs) ---"
for d in $(lsblk -rno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}'); do
  wipefs -a "$d" 2>&1 | grep -i bcache | sed 's/^/  /' || true
done
echo "rollback complete. NOTE: a backing device whose cache held DIRTY (writeback) data"
echo "and is force-run without it will corrupt its filesystem — that path is:"
echo "  echo 1 > /sys/block/<bdev-without-bcacheN>/bcache/running   # last resort only"
