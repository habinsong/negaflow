# 01 — GrainMend 검출 품질 1:1 대조

목표: **같은 사진에서 macOS 와 같은 것을 결함으로 고른다.** 지금은 먼지를 하나도 못 잡고
직선 구조물만 잡습니다.

## 0. 정답지와 현재 값

같은 사진 `OpticFilm8100_frame_4.tiff` (5088×3401), **자동** 검출.

| 분류 | macOS (정답) | Windows (지금) | 차이 |
|---|---:|---:|---:|
| 먼지 | 13 | **0** | −13 |
| 핀홀 | 2 | **0** | −2 |
| 가로 스크래치 | 5 | 3 | −2 |
| 세로 스크래치 | 10 | 11 | +1 |
| 대각 스크래치 | 0 | 1 | +1 |
| 유제 손상 | 0 | 0 | 0 |
| **미세 입자** | **197** | **1590** | **+1393** |
| **합계** | **227** | **1605** | **+1378** |

Windows 부가 정보: 평균 신뢰도 0.246, 채택 화소 10,669.

**사용자 확인 사항: macOS 에서도 오검출이 많습니다.** 즉 목표는 "오검출 0" 이 아니라
**"macOS 와 같은 것을 고른다"** 입니다. macOS 가 잡는 전봇대는 Windows 도 잡아야 하고,
macOS 가 잡는 먼지 13개도 잡아야 합니다.

### 이 표가 말하는 것

1. **스크래치 경로는 대체로 맞습니다.** 가로 3/5, 세로 11/10, 대각 1/0 — 자릿수가 같습니다.
   그래서 "직선만 잡는다"는 증상은 스크래치가 과하게 나오는 것이 아니라 **나머지가 전부
   0이라 스크래치만 남은 것**입니다.
2. **먼지·핀홀 경로가 통째로 죽어 있습니다.** 13과 2가 0입니다. `DefectDustDetector` 대조가
   최우선입니다(2.1).
3. **미세 입자가 최대 격차입니다(197 → 0).** 게다가 Windows 는 이 패스에 CPU 11초를 쓰고도
   성분을 하나도 못 냅니다 — 마스크에만 더하고 컴포넌트로 승격하지 않기 때문입니다(2.5).
   **가장 비싼 단계가 화면에 아무 기여도 못 하고 있습니다.**

4. **다른 프레임의 macOS 기준값도 있습니다** — frame_2 합계 1,720 · frame_3 623 ·
   frame_5 647 · frame_7 956. 프레임마다 더러움이 8배 차이나므로 **한 장으로 임계를 맞추면
   안 됩니다.** 전체 표: [06-detection-reference.md](06-detection-reference.md).

재현:

```bash
negaflow-cli --grain-mend-detect "<source.tiff>" <dmin-r> <dmin-g> <dmin-b> [sensitivity] [guided]
```

**이 표의 Windows 열이 macOS 열에 가까워지지 않으면 아무것도 고쳐진 것이 아닙니다.**

## 1. 이미 확인한 것

### 1.1 해상도 — 고침 (`a637e33`)

macOS 는 검출 경로가 **둘**입니다.

| macOS 함수 | 쓰는 곳 | 해상도 |
|---|---|---|
| `SoftwareDefectDetector.detect(in:)` | 브러시 | 긴 변 1800px 로 축소 |
| `SoftwareDefectDetector.detectLabeled(in:)` | 자동·가이드 | **다운스케일 없음** |
| `SoftwareDefectRemoval.detectComponents(in:)` | 자동·가이드 진입점 | ≤1400px 단일, 넘으면 halo 겹친 타일 |

Windows `detect_grain_mend` 는 `make_detection_image`(1800px 축소)를 썼습니다. 지금은
`build_tiled_automatic_mask` 로 갑니다.

### 1.2 검출 계약 — 고침 (`a637e33`)

`find_candidates(..., labeled_detection, ...)` 에 `false` 를 넘기고 있었습니다. 그것은 macOS
`detect()`(브러시) 계약입니다. 자동·가이드는 `true` 여야 하고, 그래야
strong/weak 히스테리시스와 `thinCandidatesLeveled` 합치기가 돕니다.

### 1.3 게이트 인자 — 고침 (`a637e33`)

`build_automatic_mask` 가 `dust_sensitivity = 0.0` 을 박아 넣고 고정 면적 상한을 썼습니다.
지금은 macOS 식입니다:

```
baseLong   = max(원본 폭, 원본 높이)          ← ROI 가 아니라 프레임 전체
ratio      = baseLong / 1800
baseMaxDust= max(150, round(ratio² × 150))
areaScale  = constrainedRegion ? 48 : 5
maxDustArea= baseMaxDust × (1 + dustSensitivity × areaScale)
classificationMaxDustArea = baseMaxDust × (1 + dustSensitivity × 5)
rejectLineGrid = !constrainedRegion
constrainedRegion = wholeFrameAuto ? false : (ROI ≠ 전체)
```

### 1.4 구조선 격자 배제 — 대조 완료, **차이 없음**

`gridLineDrops`(macOS) ↔ `structure_grid_drops`(Windows): 두 메커니즘(국소 밀도 A, 방향 기반 B),
`sameLineFragment`, `votesAsStructureNeighbour` 까지 같은 모양입니다. 상수 12개 전부 일치:

| 상수 | 값 |
|---|---:|
| `gridLineMinField` / `grid_line_minimum_field` | 8 |
| `gridLineMinLength` / `grid_line_minimum_length` | 6.0 |
| `gridLineRadiusMin` / `grid_line_radius_minimum` | 48 |
| `gridLineRadiusDivisor` / `grid_line_radius_divisor` | 6 |
| `gridLineDenseCount` / `grid_line_dense_count` | 5 |
| `gridLineOrientTol` / `grid_line_orientation_tolerance` | 22.0 |
| `gridLineStructRadiusDivisor` / `grid_line_structure_radius_divisor` | 4 |
| `gridLineParallelField` / `grid_line_parallel_field` | 5 |
| `gridLineMinAlong` / `grid_line_minimum_along` | 2 |
| `gridLineMinPerp` / `grid_line_minimum_perpendicular` | 2 |
| `gridLineCollinearOffset` / `grid_line_collinear_offset` | 12.0 |
| `gridLineComparableLengthRatio` / `grid_line_comparable_length_ratio` | 2.5 |

**따라서 전봇대 오검출은 격자 배제의 문제가 아닙니다.** `gridLineMinField = 8` 이라 선이
8개 미만이면 판정 자체를 시도하지 않습니다 — 전봇대 한 개 + 가로대는 그 수에 못 미칩니다.
macOS 도 같습니다. 원인은 **후보 단계에서 그 선을 스크래치로 뽑는 것**이며, 그것은 아래
2절의 미대조 파일들에 있습니다.

## 2. 아직 대조하지 않은 것 — 여기가 남은 작업

### 2.1 파일 대조표

| macOS | 줄 | Windows | 대조 |
|---|---:|---|---|
| `DefectContrastField.swift` | 199 | `grain_mend_detector.cpp` 안 | **안 함** |
| `DefectDustDetector.swift` | 176 | `grain_mend_detector.cpp` 안 | **안 함** |
| `DefectScratchDetector.swift` | 337 | `grain_mend_scratch_angles.cpp` 262 | **안 함** |
| `DefectComponentMask+Labeled.swift` | — | `grain_mend_components.cpp` | **안 함** |
| `DefectComponentMask.swift` (게이트 상수) | — | `grain_mend_component_types.h` | 일부(격자만) |
| `DefectSpeckDetector.swift` | 192 | `grain_mend_speck_detector.cpp` 317 | 알고리즘 형태만 |
| `DefectShape.swift` | 33 | `grain_mend_shape.cpp` | 이식함 |
| `DefectClassifier.swift` | 114 | `grain_mend_classifier.cpp` | 이식함 |

줄 수 차이가 큰 곳이 위험합니다: `DefectScratchDetector` 337 → 262.

### 2.2 확인해야 할 macOS 인자 — Windows 에 있는지 모름

`detectLabeledWithResponse` 가 `buildLabeled` 에 넘기는 것 전부:

| macOS 인자 | 값/식 | Windows |
|---|---|---|
| `maxDustArea` | 위 1.3 | 있음 |
| `minScratchLength` | `max(6, max(w,h) / (120 + s·120))` | 있음 |
| `minScratchAspect` | `2.5 − s·0.7` | 있음 |
| `dustMaxAspect` | `4.0 + s·4.0` | 있음 |
| `minThickDefect` | 4 | 있음 |
| `maxThickDefect` | `12 + s·12` | 있음 |
| `dustTrustedStrong` | `extendedDustScales` 일 때만 | **확인 안 됨** |
| `microDustMinArea` | `extendedDustScales ? 3 : 1` | **확인 안 됨** |
| `grainFieldSmallMax` | 제약 영역이면 `constrainedRegionGrainFieldSmallMax` | **확인 안 됨** |
| `extendedDustScales` | `constrainedRegion` | **확인 안 됨** |
| `rejectLineGrid` | `!constrainedRegion` | 있음 |
| `scratchResponse` | `deferContinuationFilter ? nil : response` | 있음 |
| `classificationMaxDustArea` | 위 1.3 | 있음 |

`extendedDustScales` 는 `DefectContrastField(rgba:width:height:parallel:extendedDustScales:)`
로도 들어갑니다 — **먼지 멀티스케일 반경 집합 자체를 바꿉니다.** Windows 는 반경을
`{4, 8, 12}` 로 고정하고 있습니다(`grain_mend_detector.cpp`). macOS 가 확장 시 어떤 반경을
쓰는지 확인해야 합니다.

### 2.3 확인해야 할 임계식

Windows 현재 값(`grain_mend_detector.cpp`):

```
dust_absolute          = 0.14 − dustSensitivity × 0.08
dust_weak_absolute     = dust_absolute × 0.5
dust_noise_multiplier  = 4.5 − dustSensitivity × 1.5
dust_strong_magnitude  = dust_absolute × (5.0 − dustSensitivity × 3.0)
dust_far_context_multiplier = 6.0
scratch_absolute       = 0.034 − scratchSensitivity × 0.014
scratch_floor_multiplier = 4.0 − scratchSensitivity × 0.8
scratch_short_floor    = scratch_absolute × 0.6
scratch_balance_limit  = 0.10 − protectDetail × 0.04
clip_high = 0.985, clip_low = 0.020
```

**하나하나 `DefectDustDetector.swift` / `DefectScratchDetector.swift` 와 대조할 것.**
검출이 먼지를 못 잡는다면 `dust_absolute` 계열이 너무 높거나 `noise_scale` 계산이 다릅니다.

### 2.4 오탐지 위험 경고 — Windows 에 없음

macOS `SoftwareDefectRemoval.applyingWholeFrameAutomaticRiskFlag`:

- 컴포넌트를 **하나도 버리지 않고** 위험 플래그만 붙입니다.
- `fraction = 후보 화소 / 전체 면적`, 한계는
  `max(wholeFrameAutomaticCandidateFractionLimit, 512 / 면적)`
- `maximumLocalCandidateDensity`: 타일변 `max(64, max(w,h)/24)` 로 나눠 가장 몰린 칸의 밀도
- 둘 중 하나라도 넘으면 위험 → 화면에 `automaticDefectFalsePositiveRiskStatus` 만 표시

Windows 에는 이 개념이 아예 없습니다. `GrainMendDetection` 에 플래그를 더하고, ABI 로 실어,
HUD 상태 문구를 macOS 와 같이 바꿔야 합니다(03 문서).

### 2.5 미세 입자 컴포넌트

macOS `DefectSpeckDetector.merged(into:specks:)` 는 **컴포넌트를 더합니다**(겹치면 기존 우선).
Windows 는 마스크에만 더합니다 — 그래서 종류별 칩에 "미세 입자"가 절대 안 나옵니다.
실측에서도 `micro_speck 0` 입니다.

## 3. 작업 순서

0절 표의 격차 크기 순서입니다.

1. **미세 입자 컴포넌트화 (197 → 0, 최대 격차)**
   `DefectSpeckDetector.merged(into:specks:)` 는 컴포넌트를 더합니다(겹치면 기존 우선).
   Windows `merge_micro_speck_mask` 는 마스크 바이트만 켭니다. 성분으로 승격해
   `collect_classified` 가 `MicroSpeck` 분류로 담게 합니다. 이 하나로 227 중 197 이 움직입니다.
   덧붙여 Windows 는 speck 이 마스크에 더하는 화소도 거의 없습니다(10,909 → 10,669 차이
   240화소) — **임계 자체가 macOS 와 다를 가능성이 큽니다.** `DefectSpeckDetector.swift` 의
   임계식을 그대로 대조하십시오.

2. **`DefectDustDetector` 대조 (13+2 → 0)**
   `candidatesLeveled` 의 strong/weak 판정식, `thinCandidatesLeveled`, `dustTrustedStrong`.
   먼지가 0이라는 것은 후보가 아예 안 서거나 게이트에서 전멸한다는 뜻입니다. 두 지점을
   따로 확인하십시오 — 후보 화소 수를 세는 계측을 임시로 넣으면 어느 쪽인지 바로 나옵니다.

3. **`DefectContrastField` 대조**
   `valid`, 멀티스케일 반경(현재 `{4,8,12}` 고정), `noise_scale`/`far_texture` 반경(12/36),
   `extendedDustScales` 의 반경 집합. 2번이 후보 부족으로 판명되면 여기가 원인입니다.

4. **`buildLabeled` 대조**
   `microDustMinArea`, `grainFieldSmallMax`, `dustTrustedStrong` 경로, 게이트 순서.
   2번이 게이트 전멸로 판명되면 여기가 원인입니다.

5. **`DefectScratchDetector` 대조 (자릿수는 맞음, 미세 조정)**
   8각도 적분, `protectDetail` 적용 지점, `candidatesLeveled` vs `candidatesWithResponse`,
   `preferredAngle`. 가로 3/5 와 대각 1/0 을 맞춥니다.

6. **위험 플래그 이식** — 2.4. macOS 도 오검출이 많으므로 이 경고는 **실제로 뜨는 기능**입니다.

7. **매 단계마다 `--grain-mend-detect` 로 재측정하고 0절 표를 갱신.**

## 4. 검증 코퍼스

| 경로 | 쓰임 |
|---|---|
| `C:\Users\habin\OneDrive\바탕 화면\negaflow_test\` | OpticFilm 8100 컬러 네거티브 15장 |
| `C:\Users\habin\Downloads\golden\golden\8100\OpticFilm8100_frame_1.tiff` | 기준 프레임 |
| `C:\Users\habin\Downloads\golden\golden\v700\GT-X900_frame_4.tiff` + `.ir.tiff` | IR 짝(유일) |

`frame_4` 는 전봇대·전선·건물 모서리가 많아 **직선 오검출 시험에 가장 좋습니다.**
`frame_1` 은 기존 성능 기준선입니다.
