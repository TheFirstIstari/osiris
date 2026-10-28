# Open PCIe Storage Carrier — Specification v0.1 (DRAFT)

**Status:** Draft for review. No PCB money moves until this spec is approved.
**Target host (reference):** Minisforum MS-A2, Ryzen 9 9955HX — PCIe x16 slot, electrical x8, BIOS split x8 / x4x4.
**Primary motivation:** expose both halves of an Intel Optane H10/H20 (x2+x2 on one M.2 socket) on hosts
without M.2 x2x2 bifurcation — plus general homelab NVMe expansion. No commercial card does this (see §9).

---

## 1. Top-level requirements

| ID | Requirement |
|----|-------------|
| R1 | **Edge:** physical x16, electrical x8 (fits x16 slots; PRSNT strapping advertises x8 per PCIe CEM). Consequence: does NOT fit physical x8 slots. |
| R2 | **Signalling:** PCIe Gen3 (8 GT/s), validated. Layout Gen4-tolerant; no Gen4 validation, no redrivers (see §7). |
| R3 | **Upstream:** x8 link to host; switch must auto-negotiate down to x4/x2/x1 (works in degraded slots). |
| R4 | **Port profiles (firmware-selectable, one PCB):** P-A = 2 ports × x4; P-B = 4 ports × x2; P-H10 = 1 socket fed by 2× x2 (lanes 0–1 from downstream port A, 2–3 from downstream port B) + remaining lanes to standard socket(s). |
| R5 | **Sockets:** 4× M.2 M-key (2280; 22110 second hole as stretch goal), single-sided placement, low-profile (half-height bracket, ≤ 64.41 mm board height, half-length ≤ 167.65 mm). |
| R6 | **No host bifurcation required.** Must enumerate on any Gen1/2/3/4/5 x8-or-wider slot via the on-board switch. |
| R7 | **OS/driver:** none. Standard PCIe bridges + NVMe endpoints only. Must work on Linux (`nvme`, `pcieport` only), and in principle any OS. |
| R8 | **License:** CERN-OHL-P v2 (precedent: open M.2 carrier work, §9). |
| R9 | **No H10 false promises:** the H10 profile is validated against the dual-`0975` enumeration test (§8). If it fails, the board is still a correct general carrier. |

---

## 2. Architecture

Single packet-switch design. No muxes, no cache controllers, no vendor blobs in the data path.

**Switch selection (primary): ASMedia ASM2824** — 24-lane / 12-port Gen3 switch, upstream x1/x2/x4/x8
with automatic lane-config detection, 16 downstream lanes, downstream ports in x1/x2/x4 increments.

| Candidate | Upstream | Downstream x2? | Availability | Verdict |
|---|---|---|---|---|
| **ASM2824** | x1/x2/x4/**x8** ✅ | yes (x1/x2/x4 increments) | Distributors/traders; no NDA wall | **Primary. Only candidate fitting x8 edge + x2 ports.** |
| ASM2812 | max x4 ❌ | yes | Same channel as above | Cost-down variant ONLY (x4-edge spin; cannot do R1). Reference design exists (RIITOP dual card, $89.99 MSRP). |
| Broadcom PEX87xx/880xx | x8+ | x2 claimed (880xx) | Distribution + NDA, docs withheld (cf. ElJefe/P411W dead end) | Rejected: unobtainable docs. |
| Microsemi PM8533 | x8 | x2 claimed | EOL-ish channel | Rejected: only reached the Optane half in the one H10 attempt on record. |
| Diodes PI7C9X2G304 | x4 | x2? | Stocked, cheap | Rejected: Gen2 silicon. |

**Why ASM2824 is load-bearing for R4:** it is the cheapest obtainable switch with BOTH an x8-capable
upstream (R1/R3) AND x2-capable downstream ports (P-B, P-H10). All cheaper options fail R1; all
Broadcom options fail obtainability.

### 2.1 Lane maps

Upstream: host lanes 0–7 → switch upstream port (x8; auto-degrades to x4/x2/x1).

| Profile | Downstream port → socket wiring | Total d/s lanes |
|---|---|---|
| P-A (2×x4) | Port0 x4 → S0 (lanes 0–3); Port1 x4 → S1 | 8 of 16 |
| P-B (4×x2) | Port0 x2 → S0; Port1 x2 → S1; Port2 x2 → S2; Port3 x2 → S3 | 8 of 16 |
| **P-H10** | **Port0 x2 → S0 lanes 0–1; Port1 x2 → S0 lanes 2–3;** Port2 x4 → S1 | 8 of 16 |

P-H10 is the entire point of this project: socket S0 carries two independent x2 links, which is what an
H10's edge expects (function 0 = Optane/SLL3D on lanes 0–1, function 1 = NAND/SM2263-65 on lanes 2–3).
No commercial card wires a socket this way — every shipping card gives each socket one x4 from one port,
which is exactly why they all show only one H10 half (PEX8747 → NAND only; PM8533 → Optane only;
ASM2812 cards → untested-split, wiring is x4-per-socket).

**Lane-reversal constraint (Intel, verified):** `1x2+1x2` is NOT a valid lane-reversal configuration —
route lanes straight, no reversal, no swapping between ports. (Intel Community, "H10 and PCIe lane reversal".)

### 2.2 Profile selection

One PCB, one EEPROM footprint, **one firmware image flashed per profile** (P-A / P-B / P-H10).
Reserve a 2-pin solder-jumper/DIP for future multi-image select; do NOT depend on switch multi-config
strapping (undocumented). Ship P-H10 as default; provide the other two images + documented reflash path
(SMBus or vendor utility) in `firmware/`.

> **Project risk RISK-1 (honest):** ASMedia EEPROM config format/tooling is not open documentation.
> Mitigation: (a) read a known-good dump from a commercial ASM2812/2824 card and adapt port-width
> fields; (b) ASMedia vendor utility via distributor FAE; (c) community dumps. No fab order until an
> EEPROM image trains all three profiles on a bench switch card or EVB.

---

## 3. Clocking, reset, sideband

- **REFCLK:** 100 MHz HCSL from edge (with SSC) → low-jitter clock buffer fanout to switch + per-socket.
  Additive jitter < 0.5 ps RMS. Common-clock architecture; no SRIS/SRNS required at Gen3.
- **CLKREQ#:** route per-socket CLKREQ# to the buffer if it supports per-output gating; default
  clocks-always-on, document the ~10s-of-mW/port cost. L1 ASPM still functional.
- **PERST#:** edge PERST# → buffer → switch + all sockets (M.2 pin 41). Correct sequencing per CEM.
- **WAKE#:** optional wire-OR to edge; document the shared-wakeup caveat for multi-function (H10) use.
- **SMBus:** edge SMBCLK/SMBDAT → switch management port; reserve debug header; fixed address plan in §6.
- **VPD/EEPROM:** config EEPROM (+ optional VPD region) on SMBus/SPI per vendor guide.
- **LEDs:** power LED per socket (minimum). Activity LED only if switch GPIO supports it (TBD in design
  phase — default to power-only rather than fake it).

---

## 4. Power

- Source: 12 V + 3.3 V from edge. M.2 sockets powered from **12 V → 3.3 V buck(s)** (edge 3.3 V pins
  cannot feed 4 sockets; budget **2.5–3 A peak per socket**, ~30–40 W worst case all-populated).
- Recommended: single 40–50 W buck module/discrete (e.g. TI TPSM84-class or TPS56xxx discrete) + per-socket
  LC filtering + inrush limiting. Small LDO for 3.3Vaux/clock/EEPROM from edge.
- Full PDN (bulk/decoupling per M.2 + switch core rails) is design-phase work; this spec sets the budget,
  not the schematic.

---

## 5. PCB / signal integrity

- **Stackup:** 4-layer minimum with impedance control (±10%, JLCPCB-capable); 6-layer if fanout demands.
  Target **85 Ω differential** (PCIe) per JLCPCB published stackup; use their impedance calculator values,
  do not invent Er.
- **Length matching:** intra-pair ≤ 5 mil, inter-pair (within a x2/x4 group) ≤ 25 mil; total Gen3 channel
  kept short (< 6 inch switch-to-socket typical). No stubs; no vias-through-splits; solid reference planes.
- **AC coupling:** 0.1 µF 0402 on all TX pairs at the transmitter (card-edge TX toward host; switch TX
  toward sockets), per PCIe CEM. (M.2 modules do not carry their own caps — the carrier provides them.)
- **Fab notes:** ENIG finish (edge-finger durability), bevelled edge fingers, impedance coupons + TDR
  report on first proto run. JLCPCB/PCBWay-class fab is acceptable for Gen3 short-reach (industry
  guidance: ±10% is workable at these rates on FR-4 for short channels; Gen4+ is where it breaks down).

---

## 6. Mechanical / form factor

- Half-height (board ≤ 64.41 mm), half-length (≤ 167.65 mm), x16 edge with x8 PRSNT strapping.
- 4× M.2 M-key sockets in-line along card length (4 × 22 mm + keepouts ≈ fits); 2280 primary,
  22110 second-hole stretch goal; double-sided SSDs must clear (4.2H components).
- Single-sided component placement (switch BGA + power on top; nothing taller than socket keepouts underneath).
- Switch thermal pad + ground-via field (BGA switches run warm; chassis airflow assumed, no fan on card).
- Half-height bracket included in BOM (sheet metal, standard LP pattern).

---

## 7. Explicit non-goals (v0.1)

- Gen4/Gen5 validation and redrivers (layout Gen4-tolerant; validated Gen3 only).
- Enterprise RAS: hot-plug sequencing validation, AER torture, SMBus management ecosystem, VPD tooling,
  compliance logos, warranty/support. This is a homelab/open-hardware board (cf. PowerRiser precedent).
- U.2/SFF-8639, OCuLink cabled variants (follow-up SKUs, same switch story).
- Any host-bifurcation dependence (R6). Any RST/Optane software (the board makes RST unnecessary).

---

## 8. Validation plan (acceptance criteria)

| # | Test | Pass criterion |
|---|---|---|
| V1 | `lspci -tv` on MS-A2 x16 slot, P-A flashed | Switch upstream x8 (or x4 if slot split x4x4 — still pass, note bandwidth) + 2 downstream bridges |
| V2 | 4× plain NVMe, P-B flashed | 4 endpoints, per-port `fio` clean, 24 h burn-in, no AER errors |
| V3 | **H10 in S0, P-H10 flashed** | **Two `8086:0975` functions** (Optane ~27 GB + NAND ~954 GB), both `nvme list`-visible, no `CSTS=0x0` |
| V4 | Link torture | Forced Gen1/2/3 stable; ASPM on/off; suspend/resume; reboot persistence |
| V5 | Thermal | Spot-check switch + bucks under full 4-drive burn-in; no throttling-induced link drops |
| V6 | H10 dual-function I/O | `fio` on both H10 halves simultaneously; `bcache`/LVM-cache smoke test on the Optane half |

Board is shippable to early users after V1+V2+V4+V5; **H10 claim only after V3+V6.**

---

## 9. References

- ASMedia ASM2812 / ASM2824 product pages (x1/x2/x4 downstream increments; upstream auto-detect):
  https://www.asmedia.com.tw/product/507Yq4asXFzi9qt4/7c5YQ79xz8urEGr1.html ·
  https://www.asmedia.com.tw/product/249yq0aSx7zRFGJ9/7c5YQ79xz8urEGr1.html
- HighPoint switch-chipset deep dive (Gen3 switch roundup): https://www.highpost-tech.com/post/exploring-the-powerhouse-a-deep-dive-into-pcie-switch-chipsets-for-pcie-gen3-m-2-nvme-cards
- RIITOP dual ASM2812 card, $89.99 MSRP, LP bracket (price anchor + proof of market):
  https://www.riitop.com/products/dual-nvme-pcie-adapter-riitop-m-2-nvme-ssd-to-pci-e-3-1-x8-x16-card-support-m-2-m-key-nvme-ssd-22110-2280-2260-2242-2230
- Intel H10 integration requirements (ASI: bifurcated x4, 2× x2 devices): https://www.asipartner.com/resources/intel-optane-memory-h10-integration-requirements/
- Intel: 1x2+1x2 lane-reversal invalid (Community "H10 and PCIe lane reversal"); install guide
  ("until acceleration is enabled the OS will show both portions as individual storage devices").
- STH "Hacking the H10/H20" (MSI Z390M both-halves report; PCH bifurcation trigger):
  https://forums.servethehome.com/index.php?threads/hacking-the-intel-h10-h20.40217/
- STH x2 bifurcation thread (tape-trick reaching NAND controller; AOC-SHG3-4M2P note):
  https://forums.servethehome.com/index.php?threads/anyone-know-of-any-pcie-or-usb-nvme-m-2-adapters-that-allow-custom-bifurcation-of-m-2-slot.42413/
- STH bifurcation x4→2×x2 thread: https://forums.servethehome.com/index.php?threads/bifurcation-x4-into-two-times-x2.37864/
- linux-nvme: Keith Busch on NAND-side init dependence (Dec 2023): https://lists.infradead.org/pipermail/linux-nvme/2023-December/043659.html
- ODROID-H4 2×2 M.2 card + BIOS (Alder Lake-N x2x2 precedent): https://wiki.odroid.com/accessory/add-on_boards/m.2_cards
- Radxa Rock 5B H10 guide (host-side x2+x2 via device tree): https://forum.radxa.com/t/guide-use-intel-optane-memory-h10-with-rock5b-pcie-splitting/11598
- Open-hardware precedents: nandfarm/PowerRiser (https://github.com/nandfarm/PowerRiser);
  Techburst36 Zero-3W carrier, CERN-OHL-P (https://github.com/Techburst36/orangepi-zero3w-m2-carrier);
  jlcjak astra_piNas (switched CM5 carrier)
- JLCPCB impedance control/stackups/calculator: https://jlcpcb.com/impedance ·
  https://jlcpcb.com/blog/pcb-pricing-breakdown
- Intel ARK N100/N150 (9× Gen3 lanes — the N-series constraint): Intel product specs 231803 / 241636
- CWWK N-series split-to-x1 ecosystem (what N-series boards do instead of x2x2): cwwk.net; STH CWWK thread

---

## 10. Open questions for review (must close before schematic)

1. ASM2824 EEPROM image source (RISK-1): dump-from-commercial-card vs distributor FAE vs community.
2. Confirm ASM2824 downstream x2-port config method (EEPROM fields) — datasheet/FAE.
3. Clock-buffer part choice (edge-REFCLK fanout, additive jitter, CLKREQ handling).
4. Single vs dual buck for socket 3.3 V; inrush strategy for 4× SSD spin-up.
5. 22110 support: keep or cut for v0.1 (length/keepout cost)?
6. Confirm MS-A2 slot delivers full x8 with `PCIe/GFX Lanes = x8` (vs x4x4) — revisit after slot-alive check.
