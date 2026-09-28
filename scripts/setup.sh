#!/usr/bin/env bash
# One-shot reproducible setup:
#   1. system packages (only missing ones)
#   2. uv
#   3. vLLM-Omni source checkout (reused if already cloned)
#   4. Python 3.12 venv + vLLM 0.30.0 + vLLM-Omni (editable)
#   5. baseline model pre-download
#   6. GPU sanity test + benchmarks/config/environment.json capture
#
# Versions are taken from the checked-out vLLM-Omni repository itself:
# docs/getting_started/quickstart.md pins `vllm==0.30.0` with
# `uv pip install vllm==0.30.0 --torch-backend=auto`, then `uv pip install -e .`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
mkdir -p logs outputs profiles benchmarks/results benchmarks/config
log() { echo "[setup $(date '+%F %T')] $*"; }

if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

# ---------------------------------------------------------------- 1. system
MISSING=()
for p in git ffmpeg jq curl wget build-essential tmux htop bc; do
    command -v "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
[ -x /usr/bin/time ] || MISSING+=("time")
if [ ${#MISSING[@]} -gt 0 ]; then
    log "installing system packages: ${MISSING[*]}"
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq "${MISSING[@]}"
else
    log "all required system packages present"
fi

# ---------------------------------------------------------------- 2. uv
if ! command -v uv >/dev/null 2>&1; then
    log "installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
command -v uv >/dev/null 2>&1 || { echo "ERROR: uv not available after install" >&2; exit 1; }
log "uv: $(uv --version)"

# ---------------------------------------------------------------- 3. vllm-omni source
if [ ! -d vllm-omni/.git ]; then
    log "cloning vllm-omni"
    git clone https://github.com/vllm-project/vllm-omni.git
fi
OMNI_SHA="$(git -C vllm-omni rev-parse HEAD)"
OMNI_SUBJECT="$(git -C vllm-omni log -1 --format='%s')"
log "vllm-omni revision: ${OMNI_SHA:0:12} ($OMNI_SUBJECT)"

# ---------------------------------------------------------------- 4. python env
if [ ! -x .venv/bin/python ]; then
    log "creating Python 3.12 venv"
    uv venv --python 3.12 --seed
fi
# shellcheck disable=SC1091
source .venv/bin/activate
log "python: $(python -V)"

# Export HF_HOME for both this script and the server (see server_env.sh).
export HF_HOME="$ROOT/.hf-cache"

VLLM_VERSION="0.30.0"
if [ "$(python -c 'import vllm,sys; print(vllm.__version__)' 2>/dev/null || true)" != "$VLLM_VERSION" ]; then
    log "installing vllm==$VLLM_VERSION (per vllm-omni quickstart) -- this downloads large wheels"
    uv pip install "vllm==$VLLM_VERSION" --torch-backend=auto
fi
log "installing vllm-omni from source (editable)"
uv pip install -e ./vllm-omni

# ---------------------------------------------------------------- 5. verify
log "verifying torch/vllm/vllm-omni"
python - <<'PY'
import torch, vllm
assert torch.cuda.is_available(), "CUDA is not available - cannot run GPU benchmark"
print("torch:", torch.__version__)
print("cuda:", torch.version.cuda)
print("device:", torch.cuda.get_device_name(0), f"({torch.cuda.get_device_properties(0).total_memory/2**30:.1f} GiB)")
print("vllm:", vllm.__version__)
import vllm_omni
print("vllm_omni:", getattr(vllm_omni, "__version__", "source-import-ok"))
PY

# ---------------------------------------------------------------- 6. model
MODEL_ID="Wan-AI/Wan2.1-T2V-1.3B-Diffusers"
log "pre-downloading $MODEL_ID (HF_HOME=$HF_HOME)"
python - "$MODEL_ID" <<'PY'
import sys
from huggingface_hub import snapshot_download
p = snapshot_download(sys.argv[1])
print("model cached at:", p)
PY

# ---------------------------------------------------------------- 7. environment.json
log "capturing benchmarks/config/environment.json"
python - "$OMNI_SHA" "$MODEL_ID" <<'PY'
import json, os, platform, socket, subprocess, sys, datetime
import torch, vllm
import vllm_omni
from huggingface_hub import model_info

omni_sha, model_id = sys.argv[1], sys.argv[2]
def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()

gpu_q = "nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader"
name, vram, driver = [x.strip() for x in sh(gpu_q).split(",")]

info = model_info(model_id)
env = {
    "timestamp": datetime.datetime.now().astimezone().isoformat(),
    "hostname": socket.gethostname(),
    "os": sh("cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2"),
    "kernel": platform.release(),
    "cpu_count": os.cpu_count(),
    "gpu": {"name": name, "vram": vram, "driver": driver},
    "cuda_version_torch": torch.version.cuda,
    "python": platform.python_version(),
    "torch": torch.__version__,
    "vllm": vllm.__version__,
    "vllm_omni": {"version": getattr(vllm_omni, "__version__", None), "git_sha": omni_sha},
    "model": {"id": model_id, "revision": info.sha},
    "env_vars": {k: os.environ.get(k) for k in ("HF_HOME", "VLLM_USE_V1", "CUDA_VISIBLE_DEVICES", "HF_HUB_ENABLE_HF_TRANSFER") if k in os.environ},
}
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__ if False else sys.argv[0]))), "benchmarks/config/environment.json")
# resolve relative to repo root regardless of invocation dir
out = os.path.join(os.getcwd(), "benchmarks/config/environment.json")
with open(out, "w") as f:
    json.dump(env, f, indent=2)
print(json.dumps(env, indent=2))
PY

log "setup complete"
