#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT="${NEGAFLOW_CATALOG_PERF_REPORT:-${ROOT}/build/performance/catalog.json}"

mkdir -p "$(dirname "$REPORT")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export NEGAFLOW_CATALOG_PERF=1
export NEGAFLOW_CATALOG_PERF_REPORT="$REPORT"

cd "$ROOT"
swift test -c release --no-parallel \
  --filter negaflowAppTests.LibraryCatalogPerformanceTests
