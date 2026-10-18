#!/usr/bin/env bash
# Shows progress of a running `crane copy` by reading the process's network byte counters (macOS).
# Usage: scripts/copy-progress.sh [total_gb]     default total = 9.04 (the vLLM image, compressed)
# Percent is an upper bound: layers that already exist in ECR are skipped, so the real total can be smaller.
set -euo pipefail

TOTAL_GB="${1:-9.04}"
PID="$(pgrep -f 'crane copy' | head -1 || true)"
[ -z "$PID" ] && { echo "no crane copy is running"; exit 0; }

read_bytes() { nettop -P -p "$PID" -L 1 -J bytes_in,bytes_out 2>/dev/null | tail -1 | awk -F, '{print $2, $3}'; }
read -r IN1 OUT1 <<< "$(read_bytes)"
sleep 10
read -r IN2 OUT2 <<< "$(read_bytes)"

python3 - "$IN2" "$OUT2" "$IN1" "$OUT1" "$TOTAL_GB" "$(ps -o etime= -p "$PID" | xargs)" <<'PY'
import sys
i2, o2, i1, o1, total, et = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), sys.argv[6]
print(f"elapsed {et}")
print(f"downloaded {i2/1e9:.2f} GB, uploaded {o2/1e9:.2f} GB of at most {total} GB ({o2/1e9/total*100:.0f}%)")
rate = (o2 - o1) / 10
print(f"upload speed now {rate*8/1e6:.1f} Mbit/s; at most {max(total - o2/1e9, 0)*1e9/rate/60:.0f} min left" if rate > 0 else "upload speed now 0 (checking layers or paused)")
PY
