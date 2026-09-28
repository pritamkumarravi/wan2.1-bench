# Baseline videos — run 20260928_055926

All videos generated from the same request:
`Wan-AI/Wan2.1-T2V-1.3B-Diffusers`, prompt *"A cinematic shot of a lone hiker
walking through a misty Himalayan valley at sunrise"*, 832x480, 81 frames,
16 fps, 20 steps, seed 42.

| File | Phase | Bytes | md5 |
|---|---|---|---|
| `video_warmup.mp4` | warmup (excluded from stats) | 744604 | same as measured |
| `video_00.mp4` … `video_04.mp4` | measured 1–5 | 744604 | `d3779da05333e880361b57208618d5e7` (all identical) |

All 6 files are **bitwise identical** — fixed seed + fixed parameters produced
byte-for-byte reproducible output on this hardware/software stack.

ffprobe facts (identical for all): h264, 832x480, 81 frames, 16/1 fps,
5.0625 s duration. `*.headers.txt` holds the raw response headers
(`X-Request-Id`, `X-Model`, `X-Inference-Time-S`).

Full metadata: `benchmarks/results/20260928_055926/`.
