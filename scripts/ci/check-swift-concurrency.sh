#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

STRICT_FLAGS=(
  -Xswiftc -warn-concurrency
  -Xswiftc -strict-concurrency=complete
  -Xswiftc -warnings-as-errors
)

swift build "${STRICT_FLAGS[@]}"
swift test "${STRICT_FLAGS[@]}"

echo "[ci-concurrency] Swift 6 strict concurrency diagnostics are clean"
