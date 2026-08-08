# macOS Film Emulation Core Image golden 생성기

## 목적

Windows에서 `CIColorCubeWithColorSpace`와 `CIUnsharpMask` 내부 동작을 추측하지 않기 위한 test-only
baseline emitter입니다. macOS 제품 구현은 바꾸지 않고 기존 `ChromabaseTests`가 같은 source를 직접
호출해 Float32 JSON을 만듭니다.

일반 `swift test`에는 파일 쓰기 side effect가 없습니다. 다음 환경변수가 명시된 단일 test만 output을
게시합니다.

```text
NEGAFLOW_WINDOWS_FILM_GOLDEN_OUTPUT=<absolute-json-path>
```

## 고정 전제

- source: `baseline/bootstrap-manifest.json`의 `source.mac_commit`
- working/output color space: extended-linear sRGB
- render format: Core Image `RGBAf`
- alpha: 현재 scanner 제품 경로와 같은 opaque
- color fixture: Windows 4×3 RGB fixture와 같은 RGB, Velvia 50 intensity 0.73
- cube 실제 양자화 강도: 0.75, dimension 33
- spatial fixture: 33×9 neutral impulse, neutral step, saturated red/green step
- radius: 1.0, 1.1, 1.2
- intensity: 실제 profile 값과 kernel 추출용 1.0

output에는 color-cube-only 4×3 값, 전체 `FilmEmulationStage` 4×3 값과 각 unsharp probe의 중앙 RGBA row가
들어갑니다. 입력과 output은 raw Float32 수치로 저장하며 이미지나 사용자 파일을 포함하지 않습니다.

## 두 context를 기록하는 이유

같은 graph를 다음 두 `CIContext`로 렌더합니다.

1. `default`: 제품과 같은 자동 backend 선택
2. `software_requested`: `useSoftwareRenderer=true` 요청

Apple 문서는 software renderer option이 지원되지 않는 플랫폼에서는 효과가 없을 수 있다고 명시합니다.
따라서 JSON의 이름은 실제 CPU 실행을 보증하지 않고 요청 mode만 기록합니다. 두 결과가 같거나 다른지는
artifact를 받은 뒤 수치로 비교합니다.

## GitHub 실행 경계

기존 `CI` workflow의 수동 실행에서만 emitter와 artifact upload가 동작합니다. 정상 PR/main push는 기존
strict-concurrency test에서 emitter가 skip되며 JSON을 만들지 않습니다. 수동 실행에서는 먼저 baseline
commit과 네 개의 Film Emulation 제품 source가 exact diff 0인지 검사합니다. 따라서 Windows branch에서
macOS 제품 수식을 몰래 바꾼 뒤 golden으로 승인하는 경로를 차단합니다.

산출물 이름은 `negaflow-windows-film-golden-<runner-commit>`이고 14일 보존합니다. JSON을 canonical
fixture로 채택하기 전에는 다음을 검토합니다.

- `mac_os_baseline_commit`과 bootstrap manifest 일치
- runner commit과 workflow run identity
- 모든 Float32 값 유한
- default/software-requested 차이
- color-only와 현재 Windows scalar 오차 분포
- impulse/step의 radius, border, channel과 overshoot 형태

검토되지 않은 workflow artifact는 Windows expected data가 아닙니다.

## canonical 실행 결과

2026-08-04 수동 run
[30919921220](https://github.com/habinsong/negaflow/actions/runs/30919921220)에서 strict-concurrency build,
emitter와 artifact upload가 통과했습니다. runner commit은
`6d9994f00f8ce3ad8c05c3ac3ae9ae33e78f0c22`, macOS 제품 기준선은
`2fa1d6297378673b58b8bec72025e968ccc3125c`입니다.

- fixture: `film-emulation-core-image-v1`, schema 1
- OS: macOS 26.5.2, build 25F84
- artifact ID: `8897230219`
- artifact digest: `sha256:f0ab00dee3bba2a356d448089750fd18115153df83253b40fac2d913b9b10ee4`
- 다운로드한 JSON SHA-256: `dc9259532eef53b7dd9cc6bbf57dc67e47bae1a19ecc355df6fcce0a65d41a80`

앞선 run과 runner commit metadata를 제외한 12,912개 numeric value는 모두 exact 일치했습니다.
`default`와 `software_requested`도 color-only, full-stage와 모든 probe에서 exact 일치했습니다. 이는 두
요청 mode의 결과가 같다는 뜻이며 실제 backend 종류를 보증하지 않습니다.

canonical artifact에서 opaque 색상 36개 RGB 값과 acutance impulse/step을 Windows fixture로 증류했습니다.
원본 JSON은 CI artifact provenance로 유지하고, test에는 필요한 합성 수치만 넣었습니다. 상세 비교는
`verification/2026-08-04-film-emulation-core-image-golden.md`에 있습니다.

## 남은 제한

- 현재 Windows 호스트에는 Core Image가 없어 같은 emitter를 로컬에서 재실행할 수 없습니다. hosted
  macOS 실행의 commit·OS·artifact digest를 함께 고정합니다.
- opaque contract만 먼저 닫습니다. fractional alpha는 scanner production route의 blocker가 아니며 별도
  fixture로 남깁니다.
- golden을 확보해도 Apple의 비공개 구현을 복제하는 것이 아니라 관측된 제품 동작에 허용오차를 맞춥니다.
