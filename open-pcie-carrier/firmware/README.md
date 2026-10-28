# Switch firmware images

One EEPROM image per port profile (see SPEC.md §2.2):

| File (planned) | Profile | Contents |
|---|---|---|
| `profile-PA-2x4.bin` | P-A | 2 downstream ports × x4 |
| `profile-PB-4x2.bin` | P-B | 4 downstream ports × x2 |
| `profile-PH10.bin` | P-H10 (default) | 2× x2 onto socket 0 (lanes 0–1, 2–3) + x4 socket 1 |

**Status: EMPTY — blocked on RISK-1** (ASMedia EEPROM config format is not open
documentation). Candidate sources, in order:

1. Read a known-good dump from a commercial ASM2812/ASM2824 card and adapt
   the port-width fields.
2. Distributor FAE / ASMedia vendor utility.
3. Community dumps.

Do not order fab until at least one image trains all downstream ports on a
bench card or EVB. Document the winning source here when found.
