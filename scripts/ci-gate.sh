#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 로컬에서 CI와 같은 검사를 한 번에 돌리는 입구다. CI(.github/workflows/ci.yml)는 같은
# 세 스크립트를 나란한 잡으로 돌리므로 내용은 같고 순서만 다르다.
bash "$ROOT/scripts/ci/verify-static.sh"
bash "$ROOT/scripts/ci/build-swift.sh"
if [ "${NEGAFLOW_CI_GUI:-0}" = "1" ]; then
  bash "$ROOT/scripts/ci/build-gui-tests.sh"
fi

echo "[ci-gate] complete"
