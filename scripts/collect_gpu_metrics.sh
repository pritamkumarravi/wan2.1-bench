#!/usr/bin/env bash
# GPU telemetry collector.
#   usage: collect_gpu_metrics.sh <output_csv> <duration_s> [interval_s]
# Samples nvidia-smi every interval (default 0.2s = 200ms) until duration
# elapses OR <output_csv>.stop appears. Never kills or slows the workload.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: collect_gpu_metrics.sh <output_csv> <duration_s> [interval_s]}"
DUR="${2:-3600}"
IV="${3:-0.2}"
STOPFLAG="${OUT}.stop"

command -v nvidia-smi >/dev/null || { echo "ERROR: nvidia-smi not found" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
rm -f "$STOPFLAG"

echo "timestamp,gpu_util_pct,mem_util_pct,vram_used_mb,vram_total_mb,power_watts,temp_c" > "$OUT"

end=$(( $(date +%s) + DUR ))
samples=0
while [ "$(date +%s)" -lt "$end" ]; do
    [ -f "$STOPFLAG" ] && break
    if row="$(nvidia-smi \
            --query-gpu=timestamp,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu \
            --format=csv,noheader,nounits 2>/dev/null)"; then
        printf '%s\n' "$row" >> "$OUT"
        samples=$(( samples + 1 ))
    fi
    sleep "$IV"
done

echo "[gpu-metrics] wrote ${samples} samples to ${OUT} (interval ${IV}s)"
