# Reference host setup — Minisforum MS-A2 (Ryzen 9 9955HX, CachyOS)

What runs on the dev box today, reproducibly:

| Layer | State |
|---|---|
| `/dev/nvme2n1` (Optane H10 XPoint 27.3G) | bcache **cache** device, 64 KiB buckets, LRU (cset `b541f58c-…`) |
| `/dev/nvme0n1` (EDILOCA 512G) | bcache **backing** device |
| `/dev/bcache0` → ext4 `slowwork` → `/srv/slow` | UUID fstab, `noatime`, weekly `fstrim` |
| Cache mode | **writethrough** (no dirty-state risk) |
| initramfs | `bcache` hook in `HOOKS`, all 3 images contain `bcache.ko.zst` + udev rules |
| Fan loop | `fan-control.sh`: powersave + 2.0 GHz cap at load < 0.5; performance + full 5.46 GHz above |

## bcache-tools (not packaged on CachyOS — build it)

```bash
# kernel.org source, verified Jun-2025 snapshot:
curl -sSL -o bt.tgz \
  https://git.kernel.org/pub/scm/linux/kernel/git/colyli/bcache-tools.git/snapshot/bcache-tools-master.tar.gz
tar xzf bt.tgz && cd bcache-tools-master && make && sudo make install
# binaries land in /usr/bin: bcache, make-bcache, bcache-super-show, probe-bcache
sudo modprobe bcache
```

**Known tool quirk (verified empirically):** this build treats `make-bcache -b` as
**bytes, not KiB** — `-b 512` writes a 512-*byte* bucket and the kernel rejects it
(`Bad bucket size (smaller than page size)`). Sweep to one page (4096) minimum;
we run **64 KiB buckets** (`-b 65536`). Sector math confirmed in
`bcache-super-show` (`sectors_per_bucket: 128`).

## Provisioning (destructive — read the script first)

`scripts/bcache-provision.sh <cache-dev> <backing-dev>` replays the verified sequence:
safety checks → stop/zero stale md → wipefs/zap → `make-bcache -C` →
register cset → `make-bcache -B --cset-uuid` → mkfs.ext4 → mount → fstab →
`HOOKS+=(bcache)` → `mkinitcpio -P`. It refuses to run if either device is mounted
or holds a live filesystem signature it doesn't recognise.

`scripts/bcache-rollback.sh` tears down in kernel-docs order
(detach → stop → unregister → wipefs) and covers the cache-loss path
(`echo 1 > /sys/block/<bdev>/bcache/running`, writethrough = safe to discard cache).

## Reboot persistence (the documented footgun)

bcache needs its udev auto-assembly **in the initramfs** or the box won't come back
("DON'T REBOOT, the machine won't come up again" — the classic Optane-cache failure).
Verify with: `lsinitcpio <image> | grep -i bcache` must show `bcache.ko.zst`,
`bcache-register`, `bcache-export-cached`, `probe-bcache`, `69-bcache.rules`.
Reboot verification on this box: **still pending** (uptime 22 days at time of writing).

## Fan control (separate concern, same box)

No PWM interface exists (BIOS owns the fans). `scripts/fan-control.sh` manages heat
instead: performance profile always active; 2.0 GHz cap at idle, full 5.46 GHz at
load ≥ 0.5. `tlp` also installed/running; `thermald` exits (non-mobile platform —
harmless). See script header for the full story, including the heredoc-quoting bug
that bit an earlier revision (always single-quote heredoc delimiters over SSH).
