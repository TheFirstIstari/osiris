#!/bin/bash
# detect-h10.sh — read-only diagnosis of Intel Optane H10/H20 hybrid visibility.
# Answers: which halves are visible, and is the missing half a firmware problem?
# Safe on any box. Requires: lspci, nvme-cli (for nvme list), root for full detail.
set -u
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
echo "=== 1. NVMe endpoints ==="
$SUDO nvme list 2>/dev/null || lspci -nn | grep -i "non-volatile"
echo
echo "=== 2. Intel 8086:0975 functions (H10/H20 Teton Glacier) ==="
COUNT=$(lspci -nn 2>/dev/null | grep -c "8086:0975" || true)
echo "0975 endpoints found: $COUNT (healthy hybrid shows 2: XPoint + NAND)"
lspci -nn 2>/dev/null | grep "8086:0975" || echo "(none)"
echo
echo "=== 3. Per-endpoint link state (expect x2 per function on a bifurcated slot) ==="
for dev in $(lspci -nn 2>/dev/null | grep "8086:0975" | cut -d" " -f1); do
  echo "--- $dev ---"
  $SUDO lspci -vvv -s "$dev" 2>/dev/null | grep -Ei "LnkCap:|LnkSta:|PhantFunc" | head -6
  echo -n "header type (offset 0x0E, bit7=multi-function): "
  HT=$($SUDO lspci -xxx -s "$dev" 2>/dev/null | sed -n '1p' | awk '{print $16}')
  if [ -n "$HT" ] && [ "$((16#${HT} & 0x80))" -ne 0 ]; then echo "0x$HT MULTI-FUNCTION";
  else echo "0x${HT:-??} single-function (an H10 half always shows single here)"; fi
done
echo
echo "=== 4. Root ports serving NVMe (look for LnkCap wider than LnkSta = unused lanes) ==="
for rp in $(lspci -nn 2>/dev/null | grep "PCI bridge" | cut -d" " -f1); do
  line=$($SUDO lspci -vvv -s "$rp" 2>/dev/null | grep -E "LnkCap:.*Width|LnkSta:.*Width" | tr '\n' '|')
  [ -n "$line" ] && echo "$rp: $line"
done
echo
echo "=== 5. Firmware bifurcation hints (AMI/AMD) ==="
ls /sys/firmware/efi/efivars/ 2>/dev/null | grep -iE "PBS|BIFUR|LANE|HYBRID" || echo "(no relevant UEFI vars)"
echo
echo "=== verdict ==="
if [ "$COUNT" -ge 2 ]; then
  echo "PASS: both H10/H20 halves visible — no adapter needed, use them directly."
elif [ "$COUNT" -eq 1 ]; then
  echo "HALF: one function only. If LnkCap x4 / LnkSta x2 above, the slot is capable but"
  echo "firmware did not bifurcate -> software cannot fix this (needs BIOS x2x2 or a"
  echo "switched carrier wiring two x2 links to one M.2 socket)."
else
  echo "NONE: no H10/H20 present on this host."
fi
