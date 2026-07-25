#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT="${NEGAFLOW_LIBRARY_QUERY_PERF_REPORT:-${ROOT}/build/library-query-performance.json}"

mkdir -p "$(dirname "${REPORT}")"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export NEGAFLOW_LIBRARY_QUERY_PERF=1
export NEGAFLOW_LIBRARY_QUERY_PERF_REPORT="${REPORT}"

cd "${ROOT}"
swift test -c release --no-parallel \
  --filter negaflowAppTests.LibraryQueryPerformanceTests
