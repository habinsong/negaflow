# DR/R/G/B 포인트 커브 scalar 구현

## 현재 범위

`chromabase-point-curve-v1`은 macOS Chroma Engine의 전체 RGB와 채널별 포인트 커브를 Windows CPU
reference로 옮긴 첫 post-pipeline 단계입니다. 입력과 출력은 extended-linear sRGB `Rgba32F`이며,
활성 커브의 lookup domain만 sRGB encoded `[0, 1]`입니다.

```text
WorkingImage의 파라메트릭 커브 결과
  → extended-linear RGB를 sRGB encode
  → [0, 1] cube domain 제한
  → 합성된 R/G/B 64표본 LUT 선형 lookup
  → sRGB decode로 extended-linear working RGB 복귀
  → 같은 WorkingImage에 제자리 저장
```

alpha는 변경하지 않습니다. 모든 커브가 identity이면 encode·clamp·decode를 생략하고 active pixel만
bit-exact로 복사하므로 음수와 1 초과 working RGB도 그대로 유지합니다.

## 파일 책임

- `point_curve.h/.cpp`: 고정 용량 제어점, 검증, LUT 생성·합성과 픽셀 kernel
- `working_tone_adjuster.h/.cpp`: 기존 tone 뒤 단계 순서, 적용 여부와 실패 시 pixel 폐기
- `point_curve_fixture.h`: 저장소 소유 3×2 합성 입력, 제어점, LUT 표본과 기대 Float32 결과
- `point_curve_tests.cpp`: 수치, identity, 정렬·끝점, 용량, stride, in-place와 실패 계약
- `scalar_conformance.cpp`: versioned fixture의 24개 RGBA 값과 오차 보고
- `develop_negative_tiff.cpp`, `export_developed_image.cpp`: 알고리즘 버전과 적용 여부 JSON

파일 I/O, TIFF container, CLI 인수 parsing과 UI 상태는 포인트 커브 kernel에 들어가지 않습니다.

## 제어점과 LUT 계약

- DR/R/G/B 각 커브의 제어점은 최대 64개입니다.
- x와 y는 유한한 `[0, 1]` 값이어야 하고, x는 정렬 후 최소 `1e-9` 간격이어야 합니다.
- 빈 커브는 `(0,0)`, `(1,1)` identity로 정규화합니다.
- 첫 x가 0보다 크거나 마지막 x가 1보다 작으면 가장 가까운 y를 끝점까지 연장합니다.
- 인접 기울기 평균과 단조성 제한을 사용해 64개의 `float` 표본을 만듭니다.
- 전체 RGB LUT를 먼저 적용하고 그 결과에 가장 가까운 채널 LUT 표본을 선택해 최종 R/G/B LUT를
  만듭니다. 이 합성은 macOS `PointCurveStage`의 64표본 recipe 의미를 보존합니다.
- 픽셀 lookup은 최종 채널 LUT의 두 이웃 표본을 선형 보간합니다.

정규화 배열은 최대 66개, 최종 LUT는 채널별 64개의 고정 배열입니다. LUT 생성과 적용 경로에는 heap
allocation이 없고 추가 full-frame image도 만들지 않습니다.

## tone orchestration

`WorkingToneAdjustParameters.point_curves`는 다음 순서의 마지막에 실행됩니다.

```text
exposure → basic tone → curve measurement → parametric curve → point curve
```

제어점 계약이 잘못되면 source pixel을 조정하기 전에 `invalid_parameter` 또는
`non_finite_parameter`로 거부합니다. 적용 중 kernel이 실패하면 owned output pixel vector를 비우고
게시 단계로 진행하지 않습니다. 기존 파라메트릭 커브 측정은 포인트 커브만 활성일 때 실행하지 않습니다.

## CLI와 UI 경계

현재 CLI와 WinUI는 임의 포인트 목록을 입력하거나 저장하지 않습니다. 기본 recipe의 빈 커브는
무연산이며 JSON에는 다음 진단 필드만 추가됩니다.

- `point_curve_algorithm_version: "chromabase-point-curve-v1"`
- `point_curve_applied: false`

native unit/conformance 경로는 활성 제어점을 직접 전달해 실제 픽셀 처리를 검증합니다. recipe ABI,
catalog serialization과 UI 편집 상태는 후속 제품 단계에서 같은 bounded 계약에 연결합니다.

## 남은 제한

- 실제 macOS Core Image 출력 golden과 Windows pixel diff가 없습니다.
- Apple 공개 문서만으로 실제 color cube의 모든 보간·반올림 세부를 확정할 수 없습니다.
- 제어점 최대 64개는 Windows의 현재 방어 경계이며 macOS UI의 실질 상한 검증이 남았습니다.
- scalar reference만 있으며 AVX2/NEON, DirectCompute/WARP 최적화는 아직 없습니다.
