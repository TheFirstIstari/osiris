#!/bin/bash
# fan-control.sh — quiet at idle, full performance at load (Minisforum MS-A2 / AMD).
#
# There is NO PWM interface on this board (BIOS owns the fans), so this script
# manages HEAT instead: the performance profile stays active at all times, and a
# CPU frequency cap keeps idle heat (and therefore BIOS fan speed) down.
#   idle (1-min load < 0.50): powersave governor + 2.0 GHz cap  -> cool, quiet
#   load (1-min load >= 0.50): performance governor + FULL cap  -> max boost
#
# History: an earlier revision of this loop was deployed with shell variables
# expanded at write time (unquoted heredoc over SSH), which froze load/temp reads
# and broke every sysfs write. This version is the corrected one: single-quote
# heredoc delimiters when installing over SSH, and it self-checks below.
# Requires: bc, root (writes under /sys). TLP may coexist (it manages AMD P-State).

FULL_MAX=5460000     # ~5.46 GHz (9955HX observed max)
QUIET_MAX=2000000    # 2.0 GHz idle cap
IDLE_LOAD=0.50

[ "$(id -u)" -eq 0 ] || { echo "run as root (writes /sys)"; exit 1; }
command -v bc >/dev/null || { echo "needs bc"; exit 1; }

# Temperature source: first k10temp hwmon (hwmon numbering is NOT stable — never hardcode hwmon4)
K10TEMP=""
for h in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$h/name" 2>/dev/null)" = "k10temp" ] && { K10TEMP="$h/temp1_input"; break; }
done
[ -n "$K10TEMP" ] || echo "WARN: no k10temp sensor found; temperature display will be N/A"

# Full cap baseline (per-CPU max may differ; use cpu0 as reference, apply to all)
REF_MAX=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo "$FULL_MAX")
trap 'echo "restoring max freq"; for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo "$REF_MAX" > "$c" 2>/dev/null || true; done; exit 0' INT TERM EXIT

echo "performance" > /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || true
echo "fan-control: PERF profile active; cap=2.0G idle / FULL at load>=0.50 (Ctrl+C restores)"

while true; do
  load1=$(awk '{print $1}' /proc/loadavg)
  if [ -n "$K10TEMP" ]; then temp_c=$(echo "scale=1; $(cat "$K10TEMP") / 1000" | bc -l)
  else temp_c="N/A"; fi
  idle=$(echo "$load1 < $IDLE_LOAD" | bc -l)
  if [ "$idle" = "1" ]; then
    for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "powersave" > "$c" 2>/dev/null || true; done
    for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo "$QUIET_MAX" > "$c" 2>/dev/null || true; done
    printf '[QUIET] load=%s temp=%sC gov=powersave cap=2.0G\n' "$load1" "$temp_c"
  else
    for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo "performance" > "$c" 2>/dev/null || true; done
    for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo "$REF_MAX" > "$c" 2>/dev/null || true; done
    printf '[PERF]  load=%s temp=%sC gov=performance cap=FULL\n' "$load1" "$temp_c"
  fi
  sleep 5
done
