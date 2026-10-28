# Project history (Oct 2026, condensed)

Reference box: `cachyos-x8664` (Minisforum MS-A2, Ryzen 9 9955HX), SSH as `powerpc`.

1. **Inventory.** 3× NVMe: Crucial 1TB (system/btrfs, 93.78% full single-copy),
   EDILOCA 512GB (stale `md127` BenchPi5:0 raid0, single member), Intel Optane H10
   27.3G (XPoint half; QLC half absent — no `09:00.1`). SMART: all PASSED, 0 errors.
   The "smartctl failure" never reproduced (stale array + no-root permission errors).
2. **Corrections.** H10 is NOT truncated — `HBRPEKNX0203A` = 32G XPoint + 1T QLC; 27.25 GiB
   is the XPoint half at full size (Intel RST CLI docs corroborate). `optane_cache` was
   never in mainline (no `drivers/memopt` at any tag). `dm-pcache` IS in-tree (7.2.8) but
   unreachable (no DAX/`nvidia-nvme`). EDILOCA "slowest drive" verdict withdrawn after
   wipe (stale raid + old data were the cause).
3. **EDILOCA reclaimed.** Stopped/zeroed md127, wiped signatures, GPT + ext4 `slowwork`,
   mounted `/srv/slow` (UUID fstab, noatime, fstrim timer). EDILOCA is write-hostile
   (12.5 ms p99.9 mixed) — read-mostly data only.
4. **bcache proven.** Built `bcache-tools` from kernel.org (units bug: `-b` is bytes;
   64 KiB buckets). Optane→EDILOCA, writethrough: 84.1k IOPS random (10.4×), sequential
   bypass confirmed, 48% hit ratio. initramfs hook installed in all 3 images.
   **Reboot persistence still untested** (box uptime 22 d at time of writing).
5. **Fan project (separate, complete).** No PWM interface; heat-managed loop:
   powersave + 2.0 GHz cap at load<0.5, performance + full 5.46 GHz above. `tlp`
   running; `thermald` exits (non-mobile platform, harmless).
6. **QLC half: impossible on MS-A2** (firmware lacks M.2 x2x2; X710 holds the only
   splittable slot; `00:01.1` unenumerated while x16 slot empty). Prior art: adapters
   reach one half at most; tape trick ends at `CSTS=0x0`. Open-carrier spec written
   (`open-pcie-carrier/SPEC.md`); N100/N150 have no documented x2x2 mini PC (ODROID-H4
   N97 is the only Alder Lake-N precedent, H10-on-H4 unconfirmed).
7. **Pending:** reboot-verify bcache; btrfs fill-state fix (needs root unmount);
   security audit; carrier schematic phase (gated on EEPROM RISK-1).
