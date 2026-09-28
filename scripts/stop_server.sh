#!/usr/bin/env bash
# Stop the vLLM-Omni server cleanly. Idempotent: safe to run repeatedly.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/scripts/server_env.sh"

if tmux has-session -t "$SERVER_SESSION" 2>/dev/null; then
    tmux kill-session -t "$SERVER_SESSION"
    echo "[stop] killed tmux session '${SERVER_SESSION}'"
else
    echo "[stop] no tmux session '${SERVER_SESSION}' (already stopped)"
fi

# Wait for the port to actually close.
for _ in $(seq 1 30); do
    if ! (echo > "/dev/tcp/127.0.0.1/${SERVER_PORT}") 2>/dev/null; then
        echo "[stop] port ${SERVER_PORT} is free"
        exit 0
    fi
    sleep 1
done

echo "[stop] WARNING: port ${SERVER_PORT} still open after 30s" >&2
exit 1
