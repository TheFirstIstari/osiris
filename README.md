# optane-hybrid-linux

**Use Intel Optane H10/H20 hybrid drives on modern Linux — without Intel RST.**

The Optane H10/H20 is one M.2 card with its x4 edge bifurcated into **two independent
x2 PCIe functions**: 3D XPoint (e.g. 27 GB) + QLC NAND (e.g. 954 GB). Intel's tooling
for it is end-of-life, the kernel driver people remember (`optane_cache`) **never
existed in mainline**, and most platforms only enumerate one half. This repo is the
honest, measured path: what works today, what is impossible and why, and the open
hardware that closes the remaining gap.

## The one-paragraph concept

PCIe bifurcation is a **platform-firmware function, executed before the OS loads**.
No driver, kernel patch, or userspace tool can conjure a PCIe function the firmware
didn't create (`PhantFunc 0`, header `0x00`, `LnkCap x4 / LnkSta x2` on our box prove
it). So the project splits cleanly:

- **What works now:** the XPoint half as a high-performance cache (`bcache`, measured
  **10.4× random-read improvement**, sequential bypass confirmed) — `host/`.
- **What needs hardware:** a carrier that presents two x2 links to *one* M.2 socket,
  so both H10 halves enumerate anywhere — `open-pcie-carrier/`. No commercial card
  does this (all give each socket one x4 from one switch port — proven one-half-only).

## Measured results (Minisforum MS-A2, Ryzen 9 9955HX, kernel 7.2.8)

| Measurement | Backing alone (EDILOCA 512G) | Through bcache0 (Optane-cached) |
|---|---|---|
| Random 4K QD1 read | 8,100 IOPS | **84,100 IOPS (10.4×)** |
| Sequential 1M QD8 read | 1,172 MiB/s | **1,676 MiB/s (1.43×**, bypass working) |
| Mixed 70/30 QD16 p99.9 | 12,517 µs | **222 µs** |

Hit ratio 48% after warmup; cache mode **writethrough** (no dirty-state risk).
Full tables: `host/docs/benchmark-results.md`.

## Repo map

```
README.md                    ← you are here (concept + setup)
.mise.toml                   ← toolchain pins (mise)
open-pcie-carrier/
  SPEC.md                    ← v0.1 hardware spec: x16-physical/x8-electrical,
                               Gen3, ASM2824, profiles 2×x4 / 4×x2 / H10 2×x2-on-one-socket
  firmware/README.md         ← EEPROM images (EMPTY — blocked on RISK-1, see spec)
  HARDWARE-LICENSE.md        ← CERN-OHL-P intent for design files
host/                        ← reference deployment on the MS-A2 dev box
  README.md                  ← host setup guide (bcache + fan control + initramfs)
  scripts/
    detect-h10.sh            ← read-only H10/bifurcation diagnosis
    bench-fio.sh             ← corrected fio harness (JSON percentile parsing fixed)
    bcache-provision.sh      ← rebuilds the verified Optane→EDILOCA bcache setup
    bcache-rollback.sh       ← safe teardown / cache-loss recovery
    fan-control.sh           ← quiet-at-idle / full-perf-at-load loop (corrected)
  docs/
    hardware-inventory.md    ← 3× NVMe, X710, slot topology, BIOS findings
    benchmark-results.md     ← full fio + hyperfine tables
    dm-pcache-verdict.md     ← why dm-pcache is unreachable here (no DAX, no nvidia-nvme)
    bifurcation-findings.md  ← platform list, adapter failures, tape-trick, ODROID/CWWK
docs/
  project-history.md         ← condensed session log: what was tried, what held up
```

## Setup — reference host (`host/`)

Prereqs: Arch/CachyOS, `nvme-cli`, `smartmontools`, `fio`, `bcache-tools` (build from
kernel.org — not in CachyOS repos; see `host/README.md`), root via sudo.

```bash
# 1. Diagnose (read-only, safe on any box):
sudo ./host/scripts/detect-h10.sh

# 2. Benchmark current drives (reads only by default):
sudo ./host/scripts/bench-fio.sh

# 3. Provision Optane-as-cache (DESTRUCTIVE to the two target drives — backups first):
sudo ./host/scripts/bcache-provision.sh /dev/nvme2n1 /dev/nvme0n1

# 4. Quiet-at-idle fan loop (AMD, BIOS-controlled fans):
sudo ./host/scripts/fan-control.sh
```

Details, fstab/initramfs notes and the rollback path: `host/README.md`.

## Setup — carrier project (`open-pcie-carrier/`)

Read `SPEC.md` first. It is a complete v0.1 spec (requirements, ASM2824 lane maps for
P-A/P-B/**P-H10**, clocking, power budget, SI rules, validation gates V1–V6) with open
questions (§10) that must close before schematic. The single blocking unknown is
**RISK-1**: ASMedia EEPROM config format — fab is gated on a working image.

## What this repo explicitly does NOT claim

- ❌ No software makes the QLC half appear on a board whose firmware doesn't bifurcate
  the M.2 slot (proven on MS-A2: no x2x2 option, X710 occupies the only splittable slot).
- ❌ `dm-pcache` is not usable here (needs `/dev/pmemX`; `nvidia-nvme` absent from kernel).
- ❌ No buyable adapter exposes both halves (PEX8747 → NAND only, PM8533 → Optane only,
  ASM2812 cards → x4-per-socket wiring, tape trick → `CSTS=0x0`).
- ✅ Everything claimed above was measured on the reference box; scripts reproduce it.

## References (primary sources)

- Intel H10 integration requirements (bifurcated x4, two x2 devices):
  https://www.asipartner.com/resources/intel-optane-memory-h10-integration-requirements/
- STH "Hacking the H10/H20" (both-halves report, MSI Z390M):
  https://forums.servethehome.com/index.php?threads/hacking-the-intel-h10-h20.40217/
- STH x2-bifurcation thread (tape trick, adapter failures):
  https://forums.servethehome.com/index.php?threads/anyone-know-of-any-pcie-or-usb-nvme-m-2-adapters-that-allow-custom-bifurcation-of-m-2-slot.42413/
- linux-nvme, Keith Busch on NAND-side init dependence (Dec 2023):
  https://lists.infradead.org/pipermail/linux-nvme/2023-December/043659.html
- ODROID-H4 2×2 M.2 card + BIOS (Alder Lake-N x2x2 precedent):
  https://wiki.odroid.com/accessory/add-on_boards/m.2_cards
- ASMedia ASM2812/ASM2824 (x1/x2/x4 downstream increments):
  https://www.asmedia.com.tw/product/507Yq4asXFzi9qt4/7c5YQ79xz8urEGr1.html
- RIITOP dual ASM2812 card, $89.99 MSRP (price anchor):
  https://www.riitop.com/products/dual-nvme-pcie-adapter-riitop-m-2-nvme-ssd-to-pci-e-3-1-x8-x16-card-support-m-2-m-key-nvme-ssd-22110-2280-2260-2242-2230
- Intel KB 000056875 (RST Windows-only; H10/H20 discontinued)
