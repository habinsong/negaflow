# 8대역 Color Mixer scalar 구현

## 현재 범위

`chromabase-color-mixer-v1`은 macOS post-pipeline의 두 번째 단계인 HSL Color Mixer를 Windows CPU
reference로 옮깁니다. 입력은 extended-linear sRGB `Rgba32F`이고, 활성 단계는 macOS kernel처럼 RGB를
`[0, 1]`로 제한한 뒤 HSL 변환을 실행합니다. 별도 sRGB encode/decode는 하지 않습니다.

```text
포인트 커브 결과의 extended-linear WorkingImage
  → 활성일 때 RGB [0, 1] clamp
  → Float32 RGB→HSL
  → 원형 hue 거리로 8대역 control 가중 평균
  → 회색 보호 gate와 hue/saturation/luminance 조정
  → Float32 HSL→RGB와 [0, 1] clamp
  → 같은 WorkingImage에 제자리 저장
```

identity면 이 전체 경로를 건너뛰고 active pixel만 bit-exact로 복사합니다. 따라서 음수와 1 초과 RGB도
조정이 없을 때는 그대로 유지됩니다. alpha는 항상 원본 값입니다.

## 파일 책임

- `color_mixer.h/.cpp`: 고정 8대역 파라미터, 검증, HSL 수학과 pointwise kernel
- `working_tone_adjuster.h/.cpp`: point curve 뒤 실행 순서, 적용 여부와 실패 시 pixel 폐기
- `color_mixer_fixture.h`: 저장소 소유 4×3 입력, 24개 control과 Float32 기대값
- `color_mixer_tests.cpp`: 수치, identity, 회색 gate, 범위, stride, in-place와 처리 순서
- `scalar_conformance.cpp`: 공통 pixel 오차 helper와 Color Mixer 48개 RGBA 값 보고
- `develop_negative_tiff.cpp`, `export_developed_image.cpp`: 알고리즘 버전과 적용 여부 JSON

수학 파일은 파일 경로, TIFF, 출력, CLI 인수, UI 상태나 동적 메모리를 소유하지 않습니다.

## 고정 수치 계약

| 항목 | 값 |
|---|---:|
| 대역 수 | 8 |
| 대역 중심 | 0°, 30°, 60°, 120°, 180°, 240°, 270°, 300° |
| 원형 삼각 가중치 폭 | hue 0.14 |
| identity 임계값 | `abs(control) < 1e-4` |
| RGB chroma 임계값 | `1e-5` |
| 회색 보호 gate | saturation 0.04~0.18 smoothstep |
| hue 이동 | `weightedHue × 0.0833` turn |
| saturation | `s × (1 + weightedSaturation × gate)` |
| luminance | `l + weightedLuminance × 0.16 × gate` |

대역 중심 사이에서는 모든 양수 가중치를 더하고 합으로 나눕니다. hue 거리는 0/1 경계를 가로지르는
최단 원형 거리입니다. macOS 이름은 `luminance`지만 실제 수식은 HSL lightness 성분을 조정합니다.

## 오류와 메모리

- 24개 control은 모두 유한한 `[-1, 1]`이어야 합니다.
- 잘못된 view, stride, capacity와 유한하지 않은 RGBA 입력을 기존 pixel contract로 거부합니다.
- parameter 실패는 source 조정 전에, kernel 실패는 결과 게시 전에 owned pixel을 폐기합니다.
- 고정 8회 loop와 stack scalar만 사용하며 heap allocation과 추가 full-frame image는 0입니다.
- identity는 layout·finite 검사 뒤 full-frame 변환 loop 없이 row copy만 수행합니다. owned orchestration은
  전체 adjustment가 identity이면 이 호출 자체를 생략합니다.

## CLI와 UI 경계

현재 CLI와 WinUI는 8대역 × 3 control 입력·serialization을 아직 노출하지 않습니다. 기본 배열은 모두
0이고 JSON에는 다음 진단 필드만 추가됩니다.

- `color_mixer_algorithm_version: "chromabase-color-mixer-v1"`
- `color_mixer_applied: false`

native unit/conformance는 활성 control을 직접 전달해 실제 픽셀 변환과 `point curve → Color Mixer` 순서를
검증합니다. UI의 기존 다국어 문자열과 8대역 slider는 catalog recipe ABI가 생길 때 같은 계약에 연결합니다.

## 남은 제한

- 실제 macOS Core Image/Metal render golden과 Windows pixel diff가 없습니다.
- 표준 HSL은 gamma-encoded sRGB를 전제로 설명되지만 macOS kernel은 linear working 값을 직접 clamp해
  사용합니다. Windows는 시각적으로 더 그럴듯한 변형 대신 현재 제품 source를 따릅니다.
- scalar reference만 있으며 AVX2/NEON, Direct2D/WARP 최적화는 아직 없습니다.
- active Color Mixer의 CLI/WinUI recipe 입력, undo와 persistence가 없습니다.
