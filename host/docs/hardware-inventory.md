# Hardware inventory — cachyos-x8664 (verified via SSH, Oct 2026)

| Item | Value |
|---|---|
| Machine | Minisforum MS-A2 (Micro Computer HK), board F1WSA, AMI Aptio BIOS 1.03 (2026-04-01) |
| CPU | AMD Ryzen 9 9955HX, 16C/32T, ~5.46 GHz max observed |
| RAM | 29 GB DDR5 (2× SO-DIMM) |
| Kernel | 7.2.8-1-cachyos |
| NICs | 2× Intel X710 SFP+ 10GbE (05:00.0/05:00.1, x4 on 00:02.1), Intel I226-V, Realtek RTL8125, MediaTek MT7922 wifi |

## NVMe

| Device | Model | Size | Role |
|---|---|---|---|
| nvme0n1 | EDILOCA EN600Pro 512GB (1d89:ef25) | 476.9 GiB | bcache backing → `/srv/slow` |
| nvme1n1 | Crucial CT1000E100SSD8 1TB (c0a9:560b) | 931.5 GiB | system disk: p1 vfat `/boot`, p2 btrfs root (single, DUP metadata, **93.78% full**) |
| nvme2n1 | **Intel Optane H10 HBRPEKNX0203AHO (8086:0975)** | **27.3 GiB** | bcache cache (XPoint half) |

## Optane H10 link facts (why the second half is missing)

- Only `09:00.0` enumerates; no `09:00.1`. Endpoint header type `0x00` (multi-function bit clear), `PhantFunc 0`.
- Root port `00:01.4`: `LnkCap x4 / LnkSta x2` — half the slot's lanes are untrained/unreachable.
- BIOS (`AMD_PBS_SETUP` UEFI var, AMI Aptio) exposes lane split **only for the PCIe x8 slot**
  (`PCIe/GFX Lanes: x8 / x4x4`); M.2 slots get speed-only settings (`SSD0/1/2 Lane Speed`).
- The x8 expansion slot is occupied by the X710 NICs; the physical x16 slot (x8 electrical)
  shows **no enumerated root port** (`00:01.1` absent) while empty — firmware hides it.
- `HBRPEKNX0203A` = 32 GB XPoint + 1 TB QLC; the visible 27.25 GiB **is the XPoint half at full,
  correct size** (Intel RST CLI docs list the Optane half of this SKU at 27 GB). Nothing is truncated.

## Drive health (smartctl, all PASSED, 0 media errors, 0 error-log entries)

- EDILOCA: 0% used, 100% spare, 61 unsafe shutdowns / 85 power cycles (rough treatment, still healthy).
- The earlier "smartctl failure" never reproduced — root cause was a stale degraded md127
  (`BenchPi5:0`, raid0, `disks=2` with one member) blocking mount, plus smartctl-without-root
  permission errors. Array destroyed, superblock zeroed.
