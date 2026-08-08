#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

bash "$ROOT/scripts/ci/check-swift-concurrency.sh"
python3 "$ROOT/scripts/ci/verify-cli-json.py"

echo "[ci-swift] complete"
