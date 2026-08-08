#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="${NEGAFLOW_PERF_REPORT_DIR:-${ROOT}/build/performance}"
MODES="${NEGAFLOW_REAL_PIXEL_ROLL_MODES:-fast-preview develop}"

mkdir -p "$REPORT_DIR"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export NEGAFLOW_REAL_PIXEL_ROLL_STRESS=1

cd "$ROOT"
for mode in $MODES; do
  if [ "$mode" != "fast-preview" ] && [ "$mode" != "develop" ]; then
    echo "[performance] ERROR: real-pixel mode must be fast-preview or develop." >&2
    exit 2
  fi
  export NEGAFLOW_REAL_PIXEL_ROLL_MODE="$mode"
  export NEGAFLOW_REAL_PIXEL_ROLL_REPORT="$REPORT_DIR/real-pixel-${mode}.json"
  swift test -c release --no-parallel \
    --filter negaflowAppTests.RollStabilityPixelStressTests
done
