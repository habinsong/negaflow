#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

export NEGAFLOW_SQLITE_CATALOG_PERF=1
export NEGAFLOW_SQLITE_CATALOG_PERF_REPORT="${NEGAFLOW_SQLITE_CATALOG_PERF_REPORT:-$ROOT/build/performance/catalog-sqlite.json}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  swift test -c release --filter LibraryCatalogSQLitePerformanceTests
