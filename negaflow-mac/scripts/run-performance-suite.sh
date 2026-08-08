#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${NEGAFLOW_PERF_MODE:-core}"
REPORT_DIR="${NEGAFLOW_PERF_REPORT_DIR:-${ROOT}/build/performance}"

if [ "${NEGAFLOW_PERF:-0}" != "1" ]; then
  echo "[performance] ERROR: set NEGAFLOW_PERF=1 to opt in." >&2
  exit 2
fi
if [ "$MODE" != "core" ] && [ "$MODE" != "full" ]; then
  echo "[performance] ERROR: NEGAFLOW_PERF_MODE must be core or full." >&2
  exit 2
fi

mkdir -p "$REPORT_DIR"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export NEGAFLOW_LIBRARY_QUERY_PERF_REPORT="$REPORT_DIR/library-query.json"
export NEGAFLOW_CATALOG_PERF_REPORT="$REPORT_DIR/catalog.json"
export NEGAFLOW_SQLITE_CATALOG_PERF_REPORT="$REPORT_DIR/catalog-sqlite.json"

bash "$ROOT/scripts/run-library-query-performance.sh"
bash "$ROOT/scripts/performance/run-catalog.sh"
bash "$ROOT/scripts/performance/run-sqlite-catalog.sh"
bash "$ROOT/scripts/performance/run-interaction.sh"
bash "$ROOT/scripts/performance/run-defect-removal.sh"

if [ "$MODE" = "full" ]; then
  bash "$ROOT/scripts/performance/run-real-pixel-roll.sh"
fi

python3 "$ROOT/scripts/performance/verify-reports.py" \
  --query "$NEGAFLOW_LIBRARY_QUERY_PERF_REPORT" \
  --catalog "$NEGAFLOW_CATALOG_PERF_REPORT" \
  --sqlite-catalog "$NEGAFLOW_SQLITE_CATALOG_PERF_REPORT"
python3 "$ROOT/scripts/performance/enforce-budgets.py" \
  --budget "${NEGAFLOW_PERF_BUDGET:-$ROOT/Config/performance-budget-v1.json}" \
  --report-directory "$REPORT_DIR" \
  --output "$REPORT_DIR/budget-report.json"
python3 "$ROOT/scripts/performance/write-manifest.py" \
  --mode "$MODE" \
  --directory "$REPORT_DIR"

echo "[performance] complete: $REPORT_DIR"
