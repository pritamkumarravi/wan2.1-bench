#!/usr/bin/env bash
# Start the vLLM-Omni server (Wan2.1-T2V-1.3B-Diffusers) inside tmux on port 8091.
# Idempotent: refuses to launch a duplicate; recovers a stale session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/server_env.sh"

CFG="${ROOT}/${BASELINE_CONFIG}"
MODEL="$(jq -r .model "$CFG")"
LOG="${ROOT}/${SERVER_LOG}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-1200}"   # seconds to wait for the server to become healthy

command -v tmux >/dev/null || { echo "ERROR: tmux not installed" >&2; exit 1; }
command -v jq   >/dev/null || { echo "ERROR: jq not installed" >&2; exit 1; }
[ -x "${ROOT}/.venv/bin/python" ] || { echo "ERROR: .venv missing - run 'make setup' first" >&2; exit 1; }

mkdir -p "$(dirname "$LOG")"
export HF_HOME="${ROOT}/.hf-cache"
CMD="vllm serve ${MODEL} --omni --port ${SERVER_PORT}"

port_open() { (echo > "/dev/tcp/127.0.0.1/${SERVER_PORT}") 2>/dev/null; }

# --- idempotency -----------------------------------------------------------
if tmux has-session -t "$SERVER_SESSION" 2>/dev/null; then
    if port_open; then
        echo "[start] server already running (tmux '$SERVER_SESSION', port ${SERVER_PORT}) - nothing to do"
        exit 0
    fi
    echo "[start] found stale tmux session without a live server - replacing it"
    tmux kill-session -t "$SERVER_SESSION"
fi

echo "[start] launching: $CMD"
echo "$CMD" > "${ROOT}/logs/server_cmd.txt"
tmux new-session -d -s "$SERVER_SESSION" \
    "cd '${ROOT}' && ${ROOT}/.venv/bin/vllm serve '${MODEL}' --omni --port ${SERVER_PORT} 2>&1 | tee -a '${LOG}'"

# --- wait until healthy ----------------------------------------------------
echo "[start] waiting up to ${WAIT_TIMEOUT}s for the server to become healthy ..."
deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
until curl -fsS -o /dev/null "http://127.0.0.1:${SERVER_PORT}/health" 2>/dev/null \
   || curl -fsS -o /dev/null "http://127.0.0.1:${SERVER_PORT}/v1/models" 2>/dev/null; do
    if ! tmux has-session -t "$SERVER_SESSION" 2>/dev/null; then
        echo "ERROR: tmux session died during startup. Last log lines:" >&2
        tail -30 "$LOG" >&2
        exit 1
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "ERROR: server not healthy after ${WAIT_TIMEOUT}s. Last log lines:" >&2
        tail -30 "$LOG" >&2
        exit 1
    fi
    sleep 5
done
echo "[start] server is healthy on port ${SERVER_PORT} (log: ${LOG})"
