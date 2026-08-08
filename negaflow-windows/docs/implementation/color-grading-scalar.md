# 3구간 Color Grading scalar 구현

## 현재 범위

`chromabase-color-grading-v1`은 macOS post-pipeline의 세 번째 단계인 Color Grading을 Windows CPU
reference로 옮깁니다. 입력은 extended-linear sRGB `Rgba32F`이며 활성 단계도 입력을 미리 제한하지
않습니다.

```text
Color Mixer 결과의 extended-linear WorkingImage
  → source RGB relative luma
  → shadows/midtones/highlights 가중치
  → HSV color-wheel tint의 zero-luma chroma와 luminance offset 합산
  → 최종 RGB [0, 1] clamp
  → 같은 WorkingImage에 제자리 저장
```

identity면 변환을 건너뛰고 active pixel만 bit-exact로 복사합니다. 따라서 음수와 1 초과 RGB도 조정이
없을 때는 그대로 유지됩니다. alpha는 항상 원본 값입니다.

## 파일 책임

- `color_grading.h/.cpp`: 세 구간 파라미터, 검증, 준비된 offset과 pointwise kernel
- `working_tone_adjuster.h/.cpp`: Color Mixer 뒤 실행 순서, 적용 여부와 실패 시 pixel 폐기
- `color_grading_fixture.h`: 저장소 소유 4×3 입력, 활성 recipe와 Float32 기대값
- `color_grading_tests.cpp`: 수치, identity, 구간 anchor, 범위, stride, in-place와 처리 순서
- `scalar_conformance.cpp`: 공통 pixel 오차 helper와 Color Grading 48개 RGBA 값 보고
- `develop_negative_tiff.cpp`, `export_developed_image.cpp`: 알고리즘 버전과 적용 여부 JSON

수학 파일은 파일 경로, TIFF, 출력, CLI 인수, UI 상태나 동적 메모리를 소유하지 않습니다.

## 파라미터 계약

| 항목 | 범위 | 기본값 |
|---|---:|---:|
| 구간 hue | 0~360° | 0° |
| 구간 saturation | 0~1 | 0 |
| 구간 luminance | -1~1 | 0 |
| blending | 0~1 | 0.5 |
| balance | -1~1 | 0 |

세 구간 모두 saturation이 `1e-4` 이하이고 luminance 절대값이 `1e-4` 이하이면 identity입니다. hue,
blending과 balance는 활성화 조건이 아닙니다. hue 360°는 0°와 같은 색으로 wrap합니다.

## 고정 수치 계약

source luma와 tint luma는 다음 계수를 사용합니다.

```text
Y = 0.2126 R + 0.7152 G + 0.0722 B
```

각 구간은 value 1의 HSV hue tint를 만들고 saturation을 곱합니다. tint의 luma를 모든 channel에서 빼서
zero-luma chroma를 만든 뒤 다음 offset을 준비합니다.

```text
regionOffset = (tint - luma(tint)) × 0.75 + luminance × 0.22
pivot = clamp(0.5 + balance × 0.30, 0.15, 0.85)
width = 0.10 × (1 - blending) + 0.50 × blending
```

pixel마다 source luma `Y`에서 다음 weight를 구합니다.

```text
transition = smoothstep(pivot - width, pivot + width, Y)
shadowWeight = 1 - transition
highlightWeight = transition
midtoneWeight = clamp(1 - abs(Y - pivot) / width, 0, 1)
```

세 `weight × regionOffset`을 source RGB에 더하고 최종 RGB만 `[0, 1]`로 제한합니다. 이 순서는 저장소의
macOS Float32 stage와 같습니다.

## 오류와 메모리

- 모든 파라미터와 RGBA 입력은 finite여야 합니다.
- 잘못된 hue/saturation/luminance/blending/balance 범위, view, stride와 capacity를 거부합니다.
- parameter 실패는 source 조정 전에, kernel 실패는 결과 게시 전에 owned pixel을 폐기합니다.
- 세 region offset, pivot과 width는 image call마다 한 번만 준비합니다.
- pixel loop는 stack scalar만 사용하며 heap allocation과 추가 full-frame image는 0입니다.
- owned orchestration은 전체 adjustment가 identity이면 kernel 호출 자체를 생략합니다.

## CLI와 UI 경계

현재 CLI와 WinUI는 세 color wheel과 luminance, blending, balance 입력·serialization을 아직 노출하지
않습니다. 기본 recipe는 identity이고 JSON에는 다음 진단 필드만 추가됩니다.

- `color_grading_algorithm_version: "chromabase-color-grading-v1"`
- `color_grading_applied: false`

native unit/conformance는 활성 recipe를 직접 전달해 실제 픽셀 변환과
`point curve → Color Mixer → Color Grading` 순서를 검증합니다. WinUI는 기존 다국어 문구와 Windows
오른쪽 caption 경계를 유지한 채 실제 Develop recipe ABI가 생길 때 연결합니다.

## 남은 제한

- 실제 macOS Core Image render golden과 Windows pixel diff가 없습니다.
- scalar reference만 있으며 AVX2/NEON, Direct2D/WARP 최적화는 아직 없습니다.
- 활성 recipe의 CLI/WinUI 입력, undo와 persistence가 없습니다.
- 현재는 최종 `[0, 1]` clamp를 macOS stage와 같이 보존하므로 뒤 단계가 받을 extended highlight는
  Color Grading이 활성일 때 제한됩니다.
