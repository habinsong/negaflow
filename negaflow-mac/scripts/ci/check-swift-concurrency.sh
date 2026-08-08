#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

STRICT_FLAGS=(
  -Xswiftc -warn-concurrency
  -Xswiftc -strict-concurrency=complete
  -Xswiftc -warnings-as-errors
)

# 자식 프로세스가 제한 시간 안에 뜨고 죽는지를 벽시계로 재는 테스트들이다. 워커 여럿과 CPU 를
# 나눠 쓰면 측정 대상이 아니라 그때의 부하를 재게 되므로(2.02초 > 2.0초 같은 실패) 직렬로 돌린다.
SERIAL_ONLY_TESTS="ExternalScannerProcessTests|testProtocolV2ViolationStopsNonExitingPluginImmediately"

swift build "${STRICT_FLAGS[@]}"
swift test --parallel "${STRICT_FLAGS[@]}" --skip "$SERIAL_ONLY_TESTS"
swift test "${STRICT_FLAGS[@]}" --filter "$SERIAL_ONLY_TESTS"

echo "[ci-concurrency] Swift 6 strict concurrency diagnostics are clean"
