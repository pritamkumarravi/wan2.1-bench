#!/usr/bin/env bash
# Convenience wrapper: smoke test, then baseline benchmark.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "${ROOT}/scripts/smoke_test.sh"
bash "${ROOT}/scripts/baseline.sh"
