#!/usr/bin/env python3
"""Summarize a baseline run directory.

usage: summarize.py <results_dir> [num_frames]

Reads requests.jsonl (tolerates both compact JSONL and pretty-printed
concatenated JSON) and gpu_metrics.csv, writes summary.json + README.md.
"""
import csv
import json
import math
import statistics
import sys
from pathlib import Path


def read_json_stream(path: Path):
    text = path.read_text()
    dec = json.JSONDecoder()
    rows, i, n = [], 0, len(text)
    while i < n:
        while i < n and text[i] in " \t\r\n":
            i += 1
        if i >= n:
            break
        obj, j = dec.raw_decode(text, i)
        rows.append(obj)
        i = j
    return rows


def main() -> None:
    resdir = Path(sys.argv[1])
    n_frames = int(sys.argv[2]) if len(sys.argv) > 2 else None
    rows = read_json_stream(resdir / "requests.jsonl")
    measured = [r for r in rows if r["phase"] == "measured"]
    if n_frames is None:
        n_frames = measured[0]["validation"].get("frame_count", 0) if measured else 0

    lat = sorted(r["wall_clock_latency_s"] for r in measured if r["http_status"] == 200)

    def pct(xs, p):
        if not xs:
            return None
        return xs[min(max(0, math.ceil(p / 100 * len(xs)) - 1), len(xs) - 1)]

    infer = [r["x_inference_time_s"] for r in measured if r.get("x_inference_time_s") is not None]
    ok = [r for r in measured if r["validation"].get("valid")]

    gpu = {"peak_vram_mb": None, "avg_gpu_utilization": None,
           "peak_gpu_utilization": None, "samples": 0}
    gf = resdir / "gpu_metrics.csv"
    if gf.exists():
        with gf.open() as f:
            r = list(csv.DictReader(f))
        if r:
            gpu = {
                "peak_vram_mb": max(float(x["vram_used_mb"]) for x in r),
                "avg_gpu_utilization": round(statistics.fmean(float(x["gpu_util_pct"]) for x in r), 2),
                "peak_gpu_utilization": max(float(x["gpu_util_pct"]) for x in r),
                "samples": len(r),
            }

    phase_wall = None
    if measured:
        phase_wall = max(float(r["end_time"]) for r in measured) - min(float(r["start_time"]) for r in measured)

    summary = {
        "run": resdir.name,
        "n_warmup": len(rows) - len(measured),
        "n_measured": len(measured),
        "n_valid_videos": len(ok),
        "latency_s": {
            "mean": round(statistics.fmean(lat), 3) if lat else None,
            "median": round(statistics.median(lat), 3) if lat else None,
            "min": round(min(lat), 3) if lat else None,
            "max": round(max(lat), 3) if lat else None,
            "p50": round(pct(lat, 50), 3) if lat else None,
            "p95": round(pct(lat, 95), 3) if lat else None,
            "p95_note": "p95 is statistically weak with only 5 samples (nearest-rank: p95 == max)",
        },
        "server_reported_inference_time_s": {"mean": round(statistics.fmean(infer), 3) if infer else None},
        "measured_phase_wall_s": round(phase_wall, 3) if phase_wall else None,
        "videos_per_second": round(len(measured) / phase_wall, 4) if phase_wall else None,
        "frames_per_second_generated": round(len(measured) * n_frames / sum(lat), 3) if lat else None,
        "gpu": gpu,
        "gpu_note": "peak_vram includes the resident server (model + CUDA context), not just per-request delta",
        "all_valid": len(ok) == len(measured) and len(measured) > 0,
    }
    (resdir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")

    md = [
        f"# Baseline run `{resdir.name}`",
        "",
        f"- warmup: {summary['n_warmup']}, measured: {summary['n_measured']} (concurrency 1), "
        f"valid videos: {summary['n_valid_videos']}",
        f"- mean latency: **{summary['latency_s']['mean']} s**, median: {summary['latency_s']['median']} s, "
        f"p95: {summary['latency_s']['p95']} s (weak, n=5)",
        "",
        f"- videos_per_second: {summary['videos_per_second']}",
        f"- frames_per_second_generated: {summary['frames_per_second_generated']}",
        f"- peak VRAM: {gpu['peak_vram_mb']} MB, avg GPU util: {gpu['avg_gpu_utilization']}% "
        f"(peak {gpu['peak_gpu_utilization']}%, {gpu['samples']} samples)",
        "",
        "Files: `config.json`, `environment.json`, `requests.jsonl`, `gpu_metrics.csv`, "
        "`summary.json`, `stdout.log`, `server_cmd.txt`.",
        "",
        f"Videos: `outputs/{resdir.name}/`",
    ]
    (resdir / "README.md").write_text("\n".join(md) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
