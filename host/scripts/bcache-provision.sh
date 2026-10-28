#!/bin/bash
# bcache-provision.sh <cache-dev> <backing-dev>
# Rebuilds the verified Optane-as-cache setup (bcache, writethrough, 64 KiB buckets).
# DESTRUCTIVE to both devices. Refuses to run on mounted devices or live roots.
# Verified on: CachyOS 7.2.8, bcache-tools built from kernel.org (Jun-2025 snapshot),
#   Optane H10 27G cache + EDILOCA 512G backing -> /dev/bcache0 -> ext4 /srv/slow.
set -u
CACHE=${1:-}; BACK=${2:-}
[ -z "$CACHE" ] || [ -z "$BACK" ] && { echo "usage: $0 /dev/nvme2n1 /dev/nvme0n1"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
[ -b "$CACHE" ] && [ -b "$BACK" ] || { echo "both args must be block devices"; exit 1; }
[ "$CACHE" = "$BACK" ] && { echo "cache and backing must differ"; exit 1; }
for d in "$CACHE" "$BACK"; do
  findmnt -S "$d" >/dev/null 2>&1 && { echo "REFUSING: $d is mounted"; exit 1; }
  lsblk -no MOUNTPOINT "$d" 2>/dev/null | grep -q . && { echo "REFUSING: partition of $d is mounted"; exit 1; }
  grep -q "$d" /etc/fstab 2>/dev/null && { echo "REFUSING: $d referenced in fstab (root?)"; exit 1; }
done
for b in bcache make-bcache bcache-super-show; do command -v $b >/dev/null || { echo "missing $b (build bcache-tools first, see host/README.md)"; exit 1; }; done
echo "ABOUT TO DESTROY: cache=$CACHE backing=$BACK"
echo "Type DESTROY to continue:"; read -r ANS; [ "$ANS" = "DESTROY" ] || { echo aborted; exit 1; }

echo "--- 1. clear stale md/raid + signatures ---"
mdadm --stop --scan 2>/dev/null || true
mdadm --zero-superblock "$BACK" 2>/dev/null || true
mdadm --zero-superblock "$CACHE" 2>/dev/null || true
wipefs -a "$CACHE" 2>&1 | tail -2
wipefs -a "$BACK" 2>&1 | tail -2
sgdisk --zap-all "$BACK" >/dev/null 2>&1 || true

echo "--- 2. format CACHE (note: -b is BYTES in this bcache-tools build; 65536 = 64 KiB) ---"
make-bcache -C -b 65536 --writeback --discard -l optanecache --force "$CACHE" 2>&1 | grep -Ei "uuid|nbuckets|bucket" || true
sleep 2
CSET=$(bcache-super-show "$CACHE" 2>/dev/null | awk '/^cset\.uuid/{print $2}')
[ -n "$CSET" ] || { echo "FATAL: no cset uuid on $CACHE"; exit 1; }
echo "cset = $CSET"
echo "$CSET" > /sys/fs/bcache/register
sleep 3
[ -d "/sys/fs/bcache/$CSET" ] || { echo "FATAL: cset did not register (dmesg | grep bcache)"; exit 1; }

echo "--- 3. format BACKING bound to cset ---"
make-bcache -B --cset-uuid "$CSET" -l backing --force "$BACK" 2>&1 | tail -6
sleep 4
BUUID=$(bcache-super-show "$BACK" 2>/dev/null | awk '/^dev\.uuid/{print $2}')
BDEV=$(readlink -f "/dev/bcache/by-uuid/$BUUID" 2>/dev/null || ls /dev/bcache[0-9]* 2>/dev/null | head -1)
[ -b "$BDEV" ] || { echo "FATAL: no bcache device appeared"; exit 1; }
echo "backing device = $BDEV"
dmesg 2>/dev/null | grep -i bcache | tail -2

echo "--- 4. filesystem + mount ---"
wipefs -a "$BDEV" 2>&1 | tail -1 || true
mkfs.ext4 -L slowwork -m 1 "$BDEV"
mkdir -p /srv/slow
UUID=$(blkid -s UUID -o value "$BDEV")
sed -i "\|/srv/slow|d" /etc/fstab
echo "UUID=$UUID /srv/slow ext4 defaults,noatime,commit=30 0 2" >> /etc/fstab
mount /srv/slow && df -hT /srv/slow | tail -1

echo "--- 5. initramfs hook (the reboot-survival step) ---"
grep -q "(^| )bcache( |$)" /etc/mkinitcpio.conf 2>/dev/null || \
  sed -i "s/^HOOKS=(base/HOOKS=(bcache base/" /etc/mkinitcpio.conf
grep -n "^HOOKS" /etc/mkinitcpio.conf
mkinitcpio -P 2>&1 | tail -3
IMG=$(find /boot -name initramfs -type f 2>/dev/null | head -1)
lsinitcpio "$IMG" 2>/dev/null | grep -c bcache | xargs echo "bcache entries in initramfs:"

echo "--- done ---"; bcache-status 2>/dev/null | head -14
echo "NOTE: final cache mode reported by the kernel on the reference box was writethrough."
