#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export NEGAFLOW_INTERACTION_PERF=1

cd "$ROOT"
swift test -c release --no-parallel \
  --filter ChromabaseTests.HighResolutionInteractionPerformanceTests
