# dm-pcache verdict: unreachable on this host (not a software gap)

`dm-pcache` (Dongsheng Yang's persistent-memory cache target) **is present** in kernel 7.2.8
(`dm-pcache.ko.zst`, `CONFIG_DM_PCACHE=m`, registers in `dmsetup targets`) — and was proven
unusable here in a live load test:

| Requirement | This host |
|---|---|
| Drive in Intel Optane cachemode namespace | ❌ plain NVMe mode (had Windows on it; `nlbaf=0`, single LBA format) |
| Switch to cachemode | ❌ `intelmas`/`isdct` EOL Mar 2025; RST is Windows-only |
| pmem-over-NVMe driver | ❌ **`nvidia-nvme` absent**: `modprobe: FATAL: Module not found` |
| `/dev/pmemX` via ndctl | ❌ no `/dev/pmem*`, no `/dev/dax*`, no `/sys/bus/nd` |
| `dmsetup create pcache_test … /dev/nvme2n1 …` | ❌ `device-mapper: reload ioctl failed: Device or resource busy` |

The docs are explicit (`cache_dev` = "Any DAX-capable block device", pure DAX-path I/O).
Without DAX there is nothing to bind. Even hypothetically, dm-pcache is writeback-only and
marked Experimental — while the working bcache setup already delivers the random-read goal.
Revisit only if a pmem path to the Optane ever exists (it currently doesn't on any kernel:
the cachemode vendor command has no open implementation).
