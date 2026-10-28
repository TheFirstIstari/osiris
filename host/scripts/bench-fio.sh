#!/bin/bash
# bench-fio.sh — fio harness with the two bugs fixed that bit the first attempt:
#   1. fio requires --name (else "No job(s) defined", empty JSON).
#   2. Percentiles live at jobs[].{read,write}.clat_ns.percentile{"50.000000": ...},
#      NOT flat lat_ns keys; and job.get('read') for a WRITE job is a truthy dict
#      of zeros — pick the direction with iops > 0.
# Reads are safe on live filesystems. Writes touch raw devices: pass --allow-write
# and name the device explicitly (default: Optane only pattern replaced by SAFETY).
set -u
SIZE=${SIZE:-3G}; RUNTIME=${RUNTIME:-12}; OUT=${OUT:-/tmp/bench_results.txt}
ALLOW_WRITE=0; WDEV=""
for a in "$@"; do case "$a" in --allow-write) ALLOW_WRITE=1;; /dev/*) WDEV="$a";; esac; done
: > "$OUT"
run() { # dev label extra testname
  local dev=$1 lbl=$2 extra=$3 name=$4 json
  json=$(mktemp /tmp/fio_out_XXXX.json)
  # shellcheck disable=SC2086
  fio --name=t --filename="$dev" --direct=1 --ioengine=libaio --numjobs=1 \
      --size="$SIZE" --runtime="$RUNTIME" --time_based --ramp_time=3 --group_reporting \
      --clat_percentiles=1,50,99,99.9 --output-format=json \
      $extra --output="$json" >/dev/null 2>&1
  [ -s "$json" ] || { echo "  !! FAILED: $lbl $name" | tee -a "$OUT"; rm -f "$json"; return; }
  python3 -c "
import json
d=json.load(open('$json'))['jobs'][0]
def pick():
    for k in ('read','write'):
        if d.get(k,{}).get('iops',0) > 0: return d[k]
    return d.get('write') or d.get('read') or {}
io=pick(); pc=io.get('clat_ns',{}).get('percentile',{})
g=lambda k:(pc.get(k,0) or 0)/1000.0
print(f\"{'$lbl':<19} {'$name':<19} IOPS={io.get('iops',0):>9.0f} BW={io.get('bw_bytes',0)/1048576:>7.0f}Mi/s  p50={g('50.000000'):>7.1f}us p99={g('99.000000'):>7.1f}us p99.9={g('99.900000'):>8.1f}us\")
" >> "$OUT" 2>/dev/null || echo "  !! PARSE FAIL: $lbl $name" | tee -a "$OUT"
  rm -f "$json"
}
declare -A LBL=()
for d in "$@"; do case "$d" in /dev/*) LBL[$d]="$d";; esac; done
[ "${#LBL[@]}" -eq 0 ] && { echo "usage: $0 [--allow-write] /dev/nvmeXnY [...]"; exit 1; }
echo "===== 4K RANDREAD QD1 (pure latency) =====" | tee -a "$OUT"
for d in "${!LBL[@]}"; do run "$d" "$(basename $d)" "--rw=randread --bs=4k --iodepth=1" "4k randread QD1"; done
echo "===== 4K RANDREAD QD32 =====" | tee -a "$OUT"
for d in "${!LBL[@]}"; do run "$d" "$(basename $d)" "--rw=randread --bs=4k --iodepth=32" "4k randread QD32"; done
echo "===== 1M SEQREAD QD16 =====" | tee -a "$OUT"
for d in "${!LBL[@]}"; do run "$d" "$(basename $d)" "--rw=read --bs=1M --iodepth=16" "1M seqread QD16"; done
if [ "$ALLOW_WRITE" = 1 ] && [ -n "$WDEV" ]; then
  echo "===== WRITES on $WDEV (explicitly allowed) =====" | tee -a "$OUT"
  run "$WDEV" "$(basename $WDEV)" "--rw=randwrite --bs=4k --iodepth=1" "4k randwrite QD1"
  run "$WDEV" "$(basename $WDEV)" "--rw=randwrite --bs=4k --iodepth=32" "4k randwrite QD32"
  run "$WDEV" "$(basename $WDEV)" "--rw=randwrite --bs=4k --iodepth=1 --fsync=1" "4k randw+fsync QD1"
  run "$WDEV" "$(basename $WDEV)" "--rw=write --bs=1M --iodepth=16" "1M seqwrite QD16"
fi
echo "results appended to $OUT"
