# R/G/B Primary Calibration scalar 구현

## 현재 범위

`chromabase-calibration-primaries-v1`은 macOS post-pipeline의 네 번째 고급 색상 단계인 Calibration을
Windows CPU reference로 옮깁니다. 이것은 장치 ICC calibration이 아니라 Develop recipe의 창의적
R/G/B primary hue·saturation 조정입니다.

```text
Color Grading 결과의 extended-linear WorkingImage
  → 활성일 때 RGB [0, 1] clamp
  → Float32 RGB→HSL
  → 원형 hue 거리로 R/G/B 세 primary control 가중 평균
  → 회색 보호 gate와 hue/saturation 조정
  → Float32 HSL→RGB와 [0, 1] clamp
  → 같은 WorkingImage에 제자리 저장
```

identity면 이 전체 경로를 건너뛰고 active pixel만 bit-exact로 복사합니다. 따라서 음수와 1 초과 RGB도
조정이 없을 때는 그대로 유지됩니다. alpha는 항상 원본 값입니다.

## 파일 책임

- `primary_calibration.h/.cpp`: 여섯 파라미터, 검증, HSL 수학과 pointwise kernel
- `working_tone_adjuster.h/.cpp`: Color Grading 뒤 실행 순서, 적용 여부와 실패 시 pixel 폐기
- `primary_calibration_fixture.h`: 저장소 소유 4×3 입력, 여섯 control과 Float32 기대값
- `primary_calibration_tests.cpp`: 수치, identity, 회색 gate, 범위, stride, in-place와 처리 순서
- `scalar_conformance.cpp`: 공통 pixel 오차 helper와 Primary Calibration 48개 RGBA 값 보고
- `develop_negative_tiff.cpp`, `export_developed_image.cpp`: 알고리즘 버전과 적용 여부 JSON

수학 파일은 파일 경로, TIFF, 출력, CLI 인수, UI 상태나 동적 메모리를 소유하지 않습니다.

## 파라미터와 identity

| primary | hue | saturation |
|---|---:|---:|
| red | -1~1 | -1~1 |
| green | -1~1 | -1~1 |
| blue | -1~1 | -1~1 |

여섯 값의 절대값이 모두 `1e-4`보다 작으면 identity입니다. macOS `isIdentity`의 strict comparison을
따르므로 정확히 `±1e-4`인 값은 단계를 활성화합니다.

## 고정 수치 계약

| 항목 | 값 |
|---|---:|
| primary 중심 | 0°, 120°, 240° |
| 원형 삼각 가중치 폭 | hue 0.22 |
| RGB chroma 임계값 | `1e-5` |
| 회색 보호 gate | saturation 0.03~0.16 smoothstep |
| hue 이동 | `weightedHue × 0.08` turn |
| saturation | `s × (1 + weightedSaturation × gate)` |

각 pixel의 HSL hue와 세 중심 사이 최단 원형 거리를 사용합니다. 폭 안의 양수 가중치를 합으로 나눠
hue와 saturation control을 각각 평균합니다. lightness는 바꾸지 않습니다. 활성 단계는 입력과 출력 RGB를
`[0, 1]`로 제한하지만 alpha는 그대로 둡니다.

## 오류와 메모리

- 여섯 control은 모두 유한한 `[-1, 1]`이어야 합니다.
- 잘못된 view, stride, capacity와 유한하지 않은 RGBA 입력을 기존 pixel contract로 거부합니다.
- parameter 실패는 source 조정 전에, kernel 실패는 결과 게시 전에 owned pixel을 폐기합니다.
- 여섯 control은 image call마다 두 개의 고정 3원소 배열로 한 번 준비합니다.
- pixel loop는 세 번의 고정 loop와 stack scalar만 사용하며 heap allocation과 추가 full-frame image는
  0입니다.
- owned orchestration은 전체 adjustment가 identity이면 kernel 호출 자체를 생략합니다.

## CLI와 UI 경계

현재 CLI와 WinUI는 red/green/blue hue·saturation 입력·serialization을 아직 노출하지 않습니다. 기본
recipe는 identity이고 JSON에는 다음 진단 필드만 추가됩니다.

- `calibration_algorithm_version: "chromabase-calibration-primaries-v1"`
- `calibration_applied: false`

native unit/conformance는 활성 control을 직접 전달해 실제 픽셀 변환과
`point curve → Color Mixer → Color Grading → Calibration` 순서를 검증합니다. WinUI는 기존 다국어
`Calibration`, `Red/Green/Blue Primary`, `Hue`, `Saturation` 문구를 실제 Develop recipe ABI가 생길 때
같은 계약에 연결합니다.

## 남은 제한

- 실제 macOS Core Image render golden과 Windows pixel diff가 없습니다.
- HSL은 gamma-encoded sRGB를 전제로 설명되지만 macOS kernel은 clamped linear working RGB에 직접
  적용합니다. Windows는 시각적 변형 대신 현재 제품 source를 따릅니다.
- scalar reference만 있으며 AVX2/NEON, Direct2D/WARP 최적화는 아직 없습니다.
- 활성 recipe의 CLI/WinUI 입력, undo와 persistence가 없습니다.
