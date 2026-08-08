# 2026-08-04 Catalog Develop route 검증

기준일: 2026-08-04
대상: `Negaflow.Catalog.Core`의 source transport/signal 분리와 legacy recipe projection

## 검증 범위

- `scanner`/`imported` transport와 film/digital signal이 서로 독립인지
- top-level/params film type 일치와 여섯 development process mapping
- explicit signal과 legacy `isDigitalSource` marker 일치
- missing legacy intensity `1.0`, 새 recipe 기본 `0.5`
- 12개 Film Emulation 이름 round trip
- unknown frame/params field 보존과 입력 object 불변
- invalid selection/record에서 부분 route 또는 부분 record를 반환하지 않는지
- object key 재귀 정렬과 array 순서 보존
- route read/write 중 이미지 파일 I/O와 SHA-256이 없는지

## 고정 fixture

`tests/fixtures/catalog/develop-route-v1.json`은 valid 5개와 invalid 17개 case를 가집니다.

Valid case에는 다음 경계를 포함합니다.

1. `imported + colorPositive + marker 없음`은 digital로 추측하지 않고 film positive로 읽음
2. explicit false marker가 있는 imported B&W negative는 film negative로 읽음
3. scanner color negative의 explicit film signal
4. imported rendered-digital color의 explicit signal+true marker
5. imported rendered-digital B&W의 explicit signal+true marker

Invalid case에는 negative+digital, signal/marker 불일치, frame/params film type 불일치, unknown profile,
강도 범위 초과, unknown/scene-linear signal과 missing params가 들어갑니다.

## 관리 코드 실행 결과

| 대상 | 결과 |
|---|---|
| x64 Debug 전체 managed solution build | 통과, 경고 0 |
| x64 Debug catalog unit | 163 assertion 통과 |
| x64 Debug 기존 shell unit | 45 assertion 통과 |
| x64 Release 전체 managed solution build | 통과, 경고 0 |
| x64 Release catalog unit | 163 assertion 통과 |
| x64 Release 기존 shell unit | 45 assertion 통과 |
| ARM64 Debug 전체 managed solution cross-build | 통과, 경고 0 |
| ARM64 Release 전체 managed solution cross-build | 통과, 경고 0 |

ARM64 test assembly는 x64 host에서 실행하지 않았으므로 ARM64 runtime assertion 통과로 표시하지
않습니다. 새 `scripts/test-managed.ps1`은 x64 Debug/Release solution을 먼저 빌드한 뒤 catalog와 shell
console unit runner를 모두 실행합니다.

## macOS 호환 test

`WindowsDevelopRouteCompatibilityTests.swift`는 같은 fixture의 valid params를 현재
`DevelopParameters`로 decode하고 다음을 확인합니다.

- film type과 profile raw value
- missing intensity의 `1.0` 복원
- explicit intensity 보존
- optional digital marker의 nil/true/false 의미
- 새 `DevelopParameters()`의 marker nil과 intensity `0.5`

현재 Windows host에는 Swift toolchain이 없어 이 새 test를 로컬에서 실행하지 않았습니다. exact commit을
push한 뒤 macOS hosted strict-concurrency CI 결과를 별도로 기록해야 합니다. 이전 Film Look 체크포인트
`259fd17eb5f7dc213a16a79e998484a72bf9f82d`의 workflow run `30928221008`은 이 변경 전 source에 대한
검증이므로 새 Swift test의 통과 증거가 아닙니다.

## 의존성·비용

- 새 NuGet/vcpkg/runtime dependency 없음
- `System.Text.Json`과 .NET base class library만 사용
- read는 이미 load된 `JsonElement`, write는 frame JSON 깊은 복사 하나만 사용
- pixel buffer, image decoder, source file open과 일반 이미지 SHA-256 호출 없음

## 남은 위험

- full catalog/SQLite transaction과 실제 앱 restart 저장·재로드는 아직 검증하지 않았습니다.
- route snapshot이 C ABI/preview/export에 아직 전달되지 않아 end-to-end source persistence는 미완료입니다.
- macOS hosted 새 fixture test는 다음 exact commit CI가 필요합니다.
- macOS/Windows canonical JSON byte와 recipe fingerprint SHA parity는 이번 범위가 아닙니다.
- actual ARM64 Windows runtime과 대형 catalog 성능은 미검증입니다.
