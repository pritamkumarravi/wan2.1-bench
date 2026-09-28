# wan21-bench

Reproducible text-to-video inference baseline: **Wan2.1-T2V-1.3B** served by
**vLLM-Omni** on a single GPU. This is the unoptimized control experiment —
fixed prompt, fixed seed, fixed shape, concurrency 1 — that future
optimizations get compared against.

## ▶ Demo

**Prompt:** *"A cinematic shot of a lone hiker walking through a misty Himalayan valley at sunrise"* — 832×480, seed 42.

| Baseline — 81 frames @ 16 fps, 20 steps (58.3 s on RTX 5090) | Smoke test — 33 frames |
|:---:|:---:|
| ![baseline demo](docs/baseline.gif) | ![smoke demo](docs/smoke.gif) |

▶ **Full-quality MP4s:** [baseline](https://github.com/pritamkumarravi/wan21-bench/releases/download/v0.1.0-baseline/wan21-baseline-832x480-81f-seed42.mp4) ·
[smoke](https://github.com/pritamkumarravi/wan21-bench/releases/download/v0.1.0-baseline/wan21-smoke-33f-seed42.mp4)
(also playable in-repo under [`outputs/`](outputs/20260928_055926/)). All 5 measured videos from the run are
bitwise identical — same bytes, same md5.

## Recorded baseline

Single NVIDIA RTX 5090 32GB · Ubuntu 24.04 · Python 3.12.3 · torch 2.13.0+cu132 ·
vLLM 0.30.0 · [vllm-omni `f5bdb20`](https://github.com/vllm-project/vllm-omni/commit/f5bdb20e9d3a2804d0cdd53f30c01b0839247ad2) ·
model [`Wan-AI/Wan2.1-T2V-1.3B-Diffusers`](https://huggingface.co/Wan-AI/Wan2.1-T2V-1.3B-Diffusers) @ `0fad780a`

| Setting | Value | | Result | Value |
|---|---|---|---|---|
| Resolution | 832×480 | | **Mean latency** | **58.291 s** |
| Frames / fps | 81 / 16 (5.06 s clip) | | Median | 58.309 s |
| Steps | 20 | | Min / Max | 58.001 / 58.479 s |
| Seed | 42 | | p95 ⚠️ | 58.479 s *(weak, n=5)* |
| Concurrency | 1 | | Throughput | 0.0171 videos/s · 1.39 frames/s |
| Requests | 1 warmup + 5 measured | | Peak VRAM | 22249 MB |
| Prompt | *"A cinematic shot of a lone hiker walking through a misty Himalayan valley at sunrise"* | | GPU util | avg 99.2%, peak 100% |

All 5 measured videos are **bitwise identical**
(`md5 d3779da0…`) — see [`outputs/20260928_055926/`](outputs/20260928_055926/).

## Repository layout

```
├── Makefile                    # setup / start / stop / smoke / baseline
├── benchmarks/
│   ├── config/baseline.json    # ALL settings live here (model, prompt, shape, seed…)
│   ├── config/environment.json # captured hardware/software provenance
│   └── results/20260928_055926/  # recorded run: requests.jsonl, gpu_metrics.csv,
│                                # summary.json, stdout.log, environment, server cmd
├── prompts/                    # Jinja2 prompt templates (.j2) — see prompts/README.md
├── outputs/
│   ├── 20260928_055926/        # the 6 generated MP4s + response headers
│   └── smoke/                  # smoke-test clip (33 frames)
├── docs/                       # README demo GIFs (from the baseline run)
├── scripts/
│   ├── setup.sh                # deps + venv + vllm 0.30.0 + vllm-omni + model + env capture
│   ├── start_server.sh         # vllm serve --omni on :8091 inside tmux (idempotent)
│   ├── stop_server.sh          # clean shutdown
│   ├── smoke_test.sh           # 1 request + ffprobe validation
│   ├── baseline.sh             # warmup + measured runs + telemetry + summary
│   ├── collect_gpu_metrics.sh  # nvidia-smi sampler (200 ms)
│   ├── render_prompt.py        # Jinja2 prompt renderer (strict vars)
│   ├── summarize.py            # summary.json / README.md generator
│   └── server_env.sh           # shared port/session paths
├── logs/                       # server log (local only, not committed)
└── profiles/                   # future optimization profiles
```

## Usage

```bash
make setup      # system deps, Python 3.12 venv, vllm==0.30.0, vllm-omni (source),
                # model download (~25 GB), GPU sanity check, environment.json
make start      # launch server in tmux on :8091, wait until healthy
make smoke      # 1 small request (33 frames), ffprobe-validated
make baseline   # 1 warmup + 5 measured, GPU telemetry, results in a new timestamped dir
make stop       # stop the server
```

Every `make baseline` run creates fresh `benchmarks/results/<ts>/` +
`outputs/<ts>/` directories — nothing is ever overwritten or deleted.
New runs stay untracked by git; recorded ones (like the baseline above) are
opted in via `.gitignore` exceptions.

## Requirements

- Linux, one CUDA GPU with ~24 GB+ free VRAM (validated on RTX 5090 32GB)
- ≥100 GB disk (model ≈ 25 GB, wheels ≈ 15 GB)
- Software pair is pinned by the vLLM-Omni repo itself: **vLLM 0.30.0** with
  the matching vLLM-Omni source checkout (`docs/getting_started/quickstart.md`)

## Prompts

Prompt text lives in **Jinja2 templates** under [`prompts/`](prompts/), selected
via `prompt_template` + `prompt_vars` in `benchmarks/config/baseline.json`.
The baseline template with no variables reproduces the recorded control prompt
byte-for-byte, and `scripts/baseline.sh` fails the run if rendering ever
drifts from the recorded literal. See [`prompts/README.md`](prompts/README.md).

## Notes

- Served via `POST /v1/videos/sync` (blocking, returns MP4 bytes) — designed
  for one-shot latency measurement; metadata arrives in the `X-Request-Id`,
  `X-Model`, and `X-Inference-Time-S` response headers.
- p95 with 5 samples is nearest-rank ≡ max — treat as an upper bound only.
- Peak VRAM includes the resident server (model + CUDA context), not a
  per-request delta.
- Fixed seed reproduces parameters and (as observed) exact bytes, but bitwise
  determinism is not guaranteed across driver/PyTorch versions.
