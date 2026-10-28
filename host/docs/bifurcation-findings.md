# Bifurcation findings (condensed — full research in session log)

## The constraint

PCIe bifurcation is firmware-created pre-OS (PCI-SIG link-subdivision whitepaper;
`iou_start_bifurcation` is one-shot; kernel has no width-change path — `bwctrl.c` only
retrains speed). An H10 needs its host x4 as **two x2 links onto one M.2 socket**.
MS-A2 has no M.2 x2x2 option (speed-only knobs); its only split (`x4x4`) is for the
PCIe slot and yields x4 ports, which still show one H10 half.

## Adapter scoreboard (all proven one-half-only or dead)

| Approach | Result |
|---|---|
| Passive M.2→PCIe carrier (any) | One x4 link → one half (AnandTech confirmed shape) |
| PEX8747 cards | NAND half only |
| Microsemi PM8533 | Optane half only |
| QNAP U2MP / ASM2812 cards | Neither (x4-per-socket wiring, not a silicon limit — ASM2812 supports x2 ports) |
| Lane-mask tape (lanes 0–1) | NAND controller reachable but `CSTS=0x0` (needs Optane half for init — K. Busch, linux-nvme) |
| Broadcom PEX880xx (P411W-32P) | Docs withheld, dead end |

## Platforms with both halves on Linux, no RST (confirmed reports)

ODROID-H3/H4 + 2×2 card/BIOS · Rock 5B (device-tree x2+x2) · MSI Z390M + H20 (PCH trigger) ·
many OEM laptops (Dell/HP/Lenovo probes) · Gigabyte G294-S41 / R264-SG2, MSI D3050MS-S3261,
AMI Elmark S2301MS (manual-documented x2x2 M.2). **Zero verified AM4/AM5 desktop reports.**
Twin Lake N150 = Alder Lake-N (9× Gen3); silicon can do x2x2 (ODROID N97 proves it) but no
N100/N150 mini PC documents it — CWWK splits to x1s.

## Other dead ends (verified)

- `optane_cache`/`drivers/memopt`: **never in mainline** (absent at every tag v4.14→master).
- `lightnvm`/`pblk`: removed in v5.15. `bcachefs`: out of mainline since v6.18 (DKMS only).
- Intel userspace: `isstcli`/`intelpmc` 404, `ipmctl`/`memkind` archived. Optane EOL Jul 2022.
- `zstd` on this box's data: 1.02× (already-compressed artifacts — compression is not a lever here).
- H10 halves are disjoint controllers/lane pairs (SLL3D vs SM2263-65) — NAND unreachable via function 0.
