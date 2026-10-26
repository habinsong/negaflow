#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/build-libraw.sh" "$(uname -m)"
export NEGAFLOW_LIBRAW_LIBRARY="$ROOT/../build/libraw/$(uname -m)/libraw.dylib"
bash "$ROOT/scripts/ci/check-swift-concurrency.sh"
python3 "$ROOT/scripts/ci/verify-cli-json.py"

echo "[ci-swift] complete"
