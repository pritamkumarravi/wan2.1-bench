#!/usr/bin/env bash
# Smoke test: reachability, one small generation, MP4 validation via ffprobe.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/server_env.sh"

CFG="${ROOT}/${BASELINE_CONFIG}"
SMOKE_DIR="${ROOT}/outputs/smoke"
VID="${SMOKE_DIR}/smoke.mp4"
HDRS="${SMOKE_DIR}/smoke_headers.txt"
mkdir -p "$SMOKE_DIR"
rm -f "$VID" "$HDRS"

# --- 1. reachability -------------------------------------------------------
if ! curl -fsS -o /dev/null "http://127.0.0.1:${SERVER_PORT}/health" 2>/dev/null \
   && ! curl -fsS -o /dev/null "http://127.0.0.1:${SERVER_PORT}/v1/models" 2>/dev/null; then
    echo "ERROR: server not reachable on port ${SERVER_PORT}. Start it with 'make start'." >&2
    exit 1
fi
echo "[smoke] server reachable on :${SERVER_PORT}"

# --- 2. one small request (33 frames keeps the smoke test fast) ------------
PROMPT="$(jq -r .prompt "$CFG")"
code="$(curl -sS -o "$VID" -D "$HDRS" -w '%{http_code}' \
    -X POST "http://127.0.0.1:${SERVER_PORT}/v1/videos/sync" \
    -F "prompt=${PROMPT}" \
    -F "size=$(jq -r .width "$CFG")x$(jq -r .height "$CFG")" \
    -F "num_frames=33" \
    -F "fps=$(jq -r .fps "$CFG")" \
    -F "num_inference_steps=$(jq -r .num_inference_steps "$CFG")" \
    -F "seed=$(jq -r .seed "$CFG")")"
echo "[smoke] HTTP ${code}"
if [ "$code" != "200" ]; then
    echo "ERROR: smoke request failed (HTTP ${code}). Response body:" >&2
    cat "$VID" >&2
    exit 1
fi
grep -iE '^x-(request-id|model|inference-time-s):' "$HDRS" || true

# --- 3./5. file exists and is a valid MP4 ----------------------------------
[ -s "$VID" ] || { echo "ERROR: output video missing/empty: $VID" >&2; exit 1; }
probe_json="$(ffprobe -v error -select_streams v:0 -count_frames \
    -show_entries stream=codec_name,width,height,nb_read_frames,avg_frame_rate \
    -show_entries format=format_name,duration,size \
    -of json "$VID")"
echo "$probe_json" | jq .
VALID="$(echo "$probe_json" | jq -r '[.streams[0].codec_name != null, .streams[0].nb_read_frames? != null] | all')"
if [ "$VALID" != "true" ]; then
    echo "ERROR: ffprobe could not validate $VID as a video file" >&2
    exit 1
fi
echo "[smoke] OK: valid MP4 at ${VID} ($(jq -r '.format.size' <<<"$probe_json") bytes)"
