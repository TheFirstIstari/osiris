# Benchmark results (fio 3.42, O_DIRECT, 3G size / 12s / 3s ramp unless noted)

Corrected run (percentiles from `clat_ns.percentile`, direction picked by iops>0 —
see `bench-fio.sh` header for the two parser bugs that voided the first run).

## Random 4K QD1 — pure latency

| Drive | IOPS | p50 | p99 | p99.9 |
|---|---|---|---|---|
| Optane H10 XPoint | 101,613 | 7.5 µs | 19.3 µs | 40.2 µs |
| Crucial E100 (system) | 21,298 | 27.3 µs | 119.3 µs | 125.4 µs |
| EDILOCA (pre-wipe, stale raid) | 12,600 | 77.5 µs | — | — |
| EDILOCA (wiped, ext4-free) | 19,857 | 16.8 µs | 125.4 µs | 140.3 µs |

## Random 4K QD32

| Drive | IOPS | p99 |
|---|---|---|
| Optane | 341,659 | 220 µs |
| Crucial | 89,603 | 1,139 µs |
| EDILOCA | 198,394 | 1,647 µs |

## Mixed 70/30 QD16 (most realistic)

| Drive | IOPS | p50 | p99.9 |
|---|---|---|---|
| Optane | 116,309 | 88.6 µs | 222 µs |
| Crucial | 21,321 | 185 µs | 840 µs |
| EDILOCA | 12,455 | 864 µs | **12,517 µs** (write-hostile — keep write-heavy work off `/srv/slow`) |

## Sequential 1M

| Drive | QD1 | QD16 |
|---|---|---|
| Optane | 1,320 MiB/s | 1,378 MiB/s (flat — latency device, no bandwidth headroom) |
| Crucial | 1,535 MiB/s | 2,344 MiB/s @3G, **decays to ~1,231 MiB/s @512MiB** (SLC-cache artifact — don't design on the burst) |
| EDILOCA | 493 MiB/s | 636 MiB/s |

## Optane writes (raw, QD1): 36,324 IOPS randwrite (p50 23.2 µs), 30,394 IOPS with fsync (p50 27.3 µs), 350 MiB/s seqwrite.

## hyperfine verdict: NOT a drive-comparison tool here

Single-command latency (436–460 µs across all drives) measured **sh-process spawn, not I/O**
(hyperfine warned: below its ~5 ms shell-calibration floor vs 8–58 µs real latency).
Only the 512 MiB sequential runs were valid (all ≈1.2–1.3 GB/s sustained). Use hyperfine
for whole-workload timing (e.g. build on `/srv/slow` vs `/home`), fio for drives.

## Through bcache0 (Optane → EDILOCA, writethrough, 64 KiB buckets, LRU)

- Random 4K QD1: **84,100 IOPS (10.4× backing's 8,100)** — 83% of raw Optane (btree lookup cost).
- Sequential 1M QD8: **1,676 MiB/s (1.43×)** — faster than either device alone (bypass + cached head).
- Sequential bypass confirmed: `bypass_hits` 8,087 → 13,092 across a 12G sequential run, occupancy flat at 2%.
- Long-run: 243,760 hits / 254,037 misses (48%), bypass hits 17,708 (26%), 348 MiB bypassed.
