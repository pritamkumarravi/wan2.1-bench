#!/usr/bin/env bash
# Baseline benchmark: 1 warmup + N measured requests (concurrency 1),
# GPU telemetry during the measured phase, per-request records, summary stats.
#
# Phases: A env capture | B health check | C warmup | D measured | E metrics
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=/dev/null
source "${ROOT}/scripts/server_env.sh"
CFG="${ROOT}/${BASELINE_CONFIG}"

# ---------------- config ----------------------------------------------------
MODEL="$(jq -r .model "$CFG")"
PROMPT="$(jq -r .prompt "$CFG")"
WIDTH="$(jq -r .width "$CFG")"
HEIGHT="$(jq -r .height "$CFG")"
NUM_FRAMES="$(jq -r .num_frames "$CFG")"
FPS="$(jq -r .fps "$CFG")"
STEPS="$(jq -r .num_inference_steps "$CFG")"
SEED="$(jq -r .seed "$CFG")"
CONCURRENCY="$(jq -r .concurrency "$CFG")"
N_MEASURED="$(jq -r .measured_requests "$CFG")"
N_WARMUP="$(jq -r .warmup_requests "$CFG")"

[ "$CONCURRENCY" = "1" ] || { echo "ERROR: baseline requires concurrency=1 (got $CONCURRENCY)" >&2; exit 1; }

STAMP="$(date +%Y%m%d_%H%M%S)"
RESDIR="${ROOT}/benchmarks/results/${STAMP}"
OUTDIR="${ROOT}/outputs/${STAMP}"
mkdir -p "$RESDIR" "$OUTDIR"

# All console output is mirrored into the run dir (stdout.log).
exec > >(tee "${RESDIR}/stdout.log") 2>&1
echo "=== baseline run ${STAMP} ==="

# ---------------- Phase A: environment capture ------------------------------
[ -f benchmarks/config/environment.json ] \
    || { echo "ERROR: benchmarks/config/environment.json missing - run 'make setup' first" >&2; exit 1; }
cp benchmarks/config/environment.json "${RESDIR}/environment.json"
cp "$CFG" "${RESDIR}/config.json"
[ -f logs/server_cmd.txt ] && cp logs/server_cmd.txt "${RESDIR}/server_cmd.txt"

# ---------------- Phase B: server health check -------------------------------
health() {
    curl -fsS -o /dev/null "http://127.0.0.1:${SERVER_PORT}/health" 2>/dev/null \
     || curl -fsS -o /dev/null "http://127.0.0.1:${SERVER_PORT}/v1/models" 2>/dev/null
}
if ! health; then
    echo "ERROR: vLLM-Omni server is not running on port ${SERVER_PORT}." >&2
    echo "       Start it first:  make start   (then: make smoke)" >&2
    exit 1
fi
echo "[phase B] server healthy on :${SERVER_PORT}"

# ---------------- request helper --------------------------------------------
# $1 = label (warmup, 00..NN); sets REQ_* variables and writes the video.
run_request() {
    local label="$1"
    local vid="${OUTDIR}/video_${label}.mp4"
    local hdrs="${OUTDIR}/video_${label}.headers.txt"
    local t0 t1 code rc=0
    t0="$(date +%s.%N)"
    code="$(curl -sS -o "$vid" -D "$hdrs" -w '%{http_code}' \
        -X POST "http://127.0.0.1:${SERVER_PORT}/v1/videos/sync" \
        -F "prompt=${PROMPT}" \
        -F "size=${WIDTH}x${HEIGHT}" \
        -F "num_frames=${NUM_FRAMES}" \
        -F "fps=${FPS}" \
        -F "num_inference_steps=${STEPS}" \
        -F "seed=${SEED}")" || rc=$?
    t1="$(date +%s.%N)"

    REQ_LABEL="$label"
    REQ_FILE="$vid"
    REQ_HTTP="$code"
    REQ_RC="$rc"
    REQ_T0="$t0"
    REQ_T1="$t1"
    REQ_ID="$(grep -i '^x-request-id:' "$hdrs" 2>/dev/null | head -1 | tr -d '\r' | awk '{print $2}')"
    REQ_INFER_S="$(grep -i '^x-inference-time-s:' "$hdrs" 2>/dev/null | head -1 | tr -d '\r' | awk '{print $2}')"
    REQ_XMODEL="$(grep -i '^x-model:' "$hdrs" 2>/dev/null | head -1 | tr -d '\r' | cut -d' ' -f2-)"
    REQ_SIZE="$(stat -c %s "$vid" 2>/dev/null || echo 0)"

    if [ "$code" = "200" ] && [ "$rc" = "0" ]; then
        REQ_PROBE="$(ffprobe -v error -select_streams v:0 -count_frames \
            -show_entries stream=codec_name,width,height,nb_read_frames,avg_frame_rate \
            -show_entries format=duration,size -of json "$vid" 2>/dev/null || echo '{}')"
        REQ_VALID="$(echo "$REQ_PROBE" | jq -r '(.streams[0].codec_name? != null) and (.streams[0].nb_read_frames? != null)')"
    else
        mv "$vid" "${vid}.error.json" 2>/dev/null || true
        REQ_FILE="${vid}.error.json"
        REQ_PROBE='{}'
        REQ_VALID="false"
    fi
    REQ_MD5="$(md5sum "$REQ_FILE" 2>/dev/null | awk '{print $1}')"
}

row_json() {  # $1 = phase
    jq -cn \
        --arg phase "$1" --arg label "$REQ_LABEL" --arg req_id "$REQ_ID" \
        --arg t0 "$REQ_T0" --arg t1 "$REQ_T1" \
        --argjson wall "$(echo "$REQ_T1 $REQ_T0" | awk '{printf "%.6f", $1-$2}')" \
        --argjson http "$REQ_HTTP" --argjson curl_rc "$REQ_RC" \
        --arg file "${REQ_FILE#$ROOT/}" --argjson bytes "$REQ_SIZE" \
        --arg infer_s "$REQ_INFER_S" --arg xmodel "$REQ_XMODEL" \
        --arg md5 "$REQ_MD5" --argjson valid "$REQ_VALID" \
        --argjson probe "$REQ_PROBE" \
        '{phase:$phase, label:$label, request_id:$req_id,
          start_time:$t0, end_time:$t1, wall_clock_latency_s:$wall,
          http_status:$http, curl_rc:$curl_rc, output_file:$file, output_size_bytes:$bytes,
          x_inference_time_s:(if $infer_s == "" then null else ($infer_s|tonumber) end),
          x_model:(if $xmodel == "" then null else $xmodel end),
          md5:$md5,
          validation:(if $valid then {valid:true,
              codec:$probe.streams[0].codec_name, width:$probe.streams[0].width,
              height:$probe.streams[0].height, frame_count:($probe.streams[0].nb_read_frames|tonumber),
              fps:$probe.streams[0].avg_frame_rate, duration_s:($probe.format.duration|tonumber)}
            else {valid:false, raw:$probe} end)}'
}

# ---------------- Phase C: warmup -------------------------------------------
echo "[phase C] warmup: ${N_WARMUP} request(s) (excluded from statistics)"
for i in $(seq 1 "$N_WARMUP"); do
    echo "[warmup $i/$N_WARMUP] generating ${NUM_FRAMES} frames @ ${WIDTH}x${HEIGHT}, ${STEPS} steps ..."
    run_request "warmup"
    row_json warmup >> "${RESDIR}/requests.jsonl"
    echo "[warmup $i/$N_WARMUP] HTTP ${REQ_HTTP}, wall $(echo "$REQ_T1 $REQ_T0" | awk '{printf "%.1fs", $1-$2}')"
done

# ---------------- Phase D + E: measured requests with GPU telemetry ----------
echo "[phase D] measured: ${N_MEASURED} request(s), concurrency ${CONCURRENCY}"
bash "${ROOT}/scripts/collect_gpu_metrics.sh" "${RESDIR}/gpu_metrics.csv" 14400 0.2 &
COLLECTOR_PID=$!
sleep 0.5   # let the collector write its header before request 1

phase_t0="$(date +%s.%N)"
for i in $(seq 0 $(( N_MEASURED - 1 ))); do
    label="$(printf '%02d' "$i")"
    echo "[measured $((i+1))/${N_MEASURED}] generating ..."
    run_request "$label"
    row_json measured >> "${RESDIR}/requests.jsonl"
    echo "[measured $((i+1))/${N_MEASURED}] HTTP ${REQ_HTTP}, wall $(echo "$REQ_T1 $REQ_T0" | awk '{printf "%.1fs", $1-$2}'), valid=${REQ_VALID}"
done
phase_t1="$(date +%s.%N)"

touch "${RESDIR}/gpu_metrics.csv.stop"
wait "$COLLECTOR_PID" 2>/dev/null || true

# ---------------- summary ----------------------------------------------------
echo "[phase E] computing summary"
python3 "${ROOT}/scripts/summarize.py" "$RESDIR" "$NUM_FRAMES"

# fail the run if any measured request did not produce a valid MP4
INVALID=$(jq -s '[.[] | select(.phase=="measured")] | map(select(.validation.valid == false)) | length' "${RESDIR}/requests.jsonl")
if [ "$INVALID" != "0" ]; then
    echo "ERROR: ${INVALID} measured request(s) produced invalid/failed output - benchmark FAILED" >&2
    exit 1
fi
echo "=== baseline run ${STAMP} complete: ${RESDIR} ==="
