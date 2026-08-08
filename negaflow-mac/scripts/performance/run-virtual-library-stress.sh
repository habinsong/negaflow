#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="${NEGAFLOW_PERF_REPORT_DIR:-${ROOT}/build/performance/virtual-library}"
ARTIFACT_ROOT="${NEGAFLOW_VIRTUAL_LIBRARY_STRESS_ROOT:-${REPORT_DIR}/catalog-root}"

mkdir -p "$REPORT_DIR"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export NEGAFLOW_VIRTUAL_LIBRARY_STRESS=1
export NEGAFLOW_VIRTUAL_LIBRARY_STRESS_KEEP="${NEGAFLOW_VIRTUAL_LIBRARY_STRESS_KEEP:-1}"
export NEGAFLOW_VIRTUAL_LIBRARY_STRESS_ROOT="$ARTIFACT_ROOT"
export NEGAFLOW_VIRTUAL_LIBRARY_STRESS_REPORT="${NEGAFLOW_VIRTUAL_LIBRARY_STRESS_REPORT:-${REPORT_DIR}/report.json}"

cd "$ROOT"
swift test -c release --no-parallel \
  --filter negaflowAppTests.VirtualLibraryCatalogStressTests
