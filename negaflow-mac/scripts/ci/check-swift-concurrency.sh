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
# GPU 정착 완료를 20초 안에 기다리는 화면/출력 시험도 같은 원칙으로 직렬 실행합니다.
# 병렬 Core Image 작업의 대기 시간을 앱 자체의 정착 지연으로 잘못 판정하지 않습니다.
SERIAL_ONLY_TESTS="ExternalScannerProcessTests|testProtocolV2ViolationStopsNonExitingPluginImmediately|DevelopExportPrintWorkflowTests"

swift build "${STRICT_FLAGS[@]}"
swift test --parallel "${STRICT_FLAGS[@]}" --skip "$SERIAL_ONLY_TESTS"
swift test "${STRICT_FLAGS[@]}" --filter "$SERIAL_ONLY_TESTS"

echo "[ci-concurrency] Swift 6 strict concurrency diagnostics are clean"
