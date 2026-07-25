#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$ROOT/scripts/ci/verify-static.sh"
bash "$ROOT/scripts/ci/build-swift.sh"
if [ "${NEGAFLOW_CI_GUI:-0}" = "1" ]; then
  bash "$ROOT/scripts/ci/build-gui-tests.sh"
fi

echo "[ci-gate] complete"
