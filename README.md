# wan21-bench — reproducible Wan2.1-T2V-1.3B inference baseline on vLLM-Omni

This project benchmarks **text-to-video inference latency** for
`Wan-AI/Wan2.1-T2V-1.3B-Diffusers` served by
[vLLM-Omni](https://github.com/vllm-project/vllm-omni) on a single NVIDIA GPU.

It is a **control experiment**: a fixed prompt, fixed seed, fixed resolution,
fixed frame count, fixed step count, concurrency 1 — no optimizations. Later
work (caching, compilation, alternative models) is compared against this
baseline.

## Hardware assumptions

Provisioned for a single-GPU Linux box with ~32 GB VRAM (validated on
**RTX 5090 32GB**, driver 595.91.07), Ubuntu 24.04, ≥64 GB system RAM,
≥100 GB free disk (model ≈ 25 GB + venv ≈ 15 GB). Everything runs on the GPU
box; nothing in the repo hard-codes machine-specific paths.

## Software pair (taken from the checked-out vLLM-Omni itself)

Per `docs/getting_started/quickstart.md` of the cloned revision, the release
line is pinned: **vLLM 0.30.0** + vLLM-Omni **0.30.x line** (source install).
The exact installed commit is recorded in
`benchmarks/config/environment.json` after `make setup`.

## Installation

```bash
make setup     # system deps (missing ones only) + uv + Python 3.12 venv
               # + vllm==0.30.0 --torch-backend=auto + vllm-omni (editable)
               # + model pre-download + GPU sanity check + environment.json
```

Idempotent: safe to re-run; already-installed pieces are skipped.

## Starting the server

```bash
make start     # vllm serve Wan-AI/Wan2.1-T2V-1.3B-Diffusers --omni --port 8091
               # inside tmux session 'wan21-server', logs -> logs/server.log
make stop      # kill the tmux session, wait for the port to close
```

`make start` is idempotent (refuses duplicates, recovers stale sessions) and
returns only once `/health` answers.

## Smoke test

```bash
make smoke     # 1 small request (33 frames) -> outputs/smoke/smoke.mp4
               # validated with ffprobe; fails on invalid MP4
```

## Baseline benchmark

```bash
make baseline  # 1 warmup + 5 measured requests, concurrency 1
```

Per run it: captures the environment, health-checks the server, runs the
warmup (excluded from stats), runs 5 measured generations while sampling
`nvidia-smi` at 200 ms, ffprobe-validates every video, and writes a summary.

## Where results are stored

```
benchmarks/results/YYYYMMDD_HHMMSS/
├── config.json         # copy of benchmarks/config/baseline.json
├── environment.json    # GPU/driver/CUDA/Python/torch/vLLM/omni-SHA/model revision
├── server_cmd.txt      # exact server launch command
├── requests.jsonl      # one record per request (warmup + measured)
├── gpu_metrics.csv     # 200 ms telemetry during the measured phase
├── summary.json        # latency stats, throughput, GPU peaks
├── stdout.log          # full console output of the run
└── README.md           # human-readable run summary

outputs/YYYYMMDD_HHMMSS/  # generated MP4s + saved response headers
```

Nothing is ever overwritten or deleted: every run gets a fresh timestamped
directory. `make clean-logs` only removes `logs/*.log`.

## What the metrics mean

- `wall_clock_latency_s` — client-side end-to-end time per request (curl).
- `x_inference_time_s` — server-reported inference time from the
  `X-Inference-Time-S` response header (detected, not assumed).
- `mean / median / min / max / p50 / p95` — over the 5 measured requests.
  **p95 is statistically weak with n=5** (nearest-rank p95 ≡ max); treat it as
  an upper bound, not a distribution estimate.
- `videos_per_second` — measured requests ÷ measured-phase wall clock.
- `frames_per_second_generated` — total frames ÷ summed latencies.
- `gpu.peak_vram_mb / avg_gpu_utilization / peak_gpu_utilization` — from the
  `nvidia-smi` telemetry sampled during the measured phase only.
- `validation` — per-video ffprobe facts (codec, WxH, exact frame count via
  `-count_frames`, fps, duration, bytes) + md5. The benchmark exits non-zero
  if any measured video is invalid.

## Reproducing the experiment

1. `make setup` — then diff `benchmarks/config/environment.json` against the
   recorded one (GPU model, driver, CUDA, torch, vLLM, vLLM-Omni SHA, model
   revision).
2. `make start && make smoke` — confirm the stack works.
3. `make baseline` — the run dir contains everything needed to answer
   *"exactly what software, hardware, model, and parameters produced this
   result?"*: `environment.json`, `config.json`, `server_cmd.txt`,
   `requests.jsonl` (including seed 42 and the fixed prompt), `gpu_metrics.csv`.

Configuration lives in **one** file, `benchmarks/config/baseline.json`
(model, prompt, 832×480, 81 frames, fps 16, 20 steps, seed 42, 1 warmup +
5 measured). Scripts read it; the prompt is never duplicated elsewhere.

## Notes

- The server runs in tmux, so SSH disconnects do not kill it. Attach with
  `tmux attach -t wan21-server` to watch live logs, or `make logs`.
- `/v1/videos/sync` is used (blocking, returns raw MP4 bytes) because this
  benchmark is a simple request/response latency measurement.
- GPU nondeterminism: fixed seed makes runs reproducible at the parameter
  level; bitwise-identical frames are not guaranteed on consumer GPUs.
