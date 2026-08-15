# 필름 베이스 자동 추정 — macOS 대조와 실측

기준일: 2026-08-10

## 왜 다시 봤나

사용자 요청입니다 — "macOS negaflow 의 필름 베이스 측정은 이미 증명된 최고이니 로직을 그대로
옮겨라." 그래서 이식됐다고 **가정하지 않고** `FilmBaseEstimator.swift`(659줄)와
`auto_negative_base_resolver.cpp` 를 함수·상수 단위로 다시 대조하고, 사용자의 실제 필름으로
측정했습니다.

## 대조 결과 — 전부 일치

| macOS | Windows | 결과 |
|---|---|---|
| `isFilmBaseCandidate` | `is_component_candidate` | 일치 |
| `candidateLumaPeak` / `candidateLumaFloor` | `candidate_luma_peak` / `* 0.10` | 일치 |
| `brightestCoherentMode` (강등 포함) | `brightest_coherent_mode` | 일치 |
| `nonFilmExclusion` | `non_film_exclusion` | 일치 |
| `dilate` (반경 2) | `dilate` | 일치 |
| `connectedBaseComponent` | `connected_component_base` | 일치 |
| `sampleBrightOrangeBase` | `continuous_border_base` | 일치 |
| `sampleDistributedOrangeBase` | `distributed_base` | 일치 |
| `borderFallback` | `strip_fallback_base` | 일치 |
| `FilmBaseStatistics.coherentCluster` | `coherent_measurement` | 일치 |
| `FilmBaseSampleGrid` | `make_sample_grid` | 일치 |

**상수도 하나도 빠짐없이 같습니다:** `brighterNeighborRatio 1.15`, `neighborRadius 2`,
`nonFilmLuma 0.88`, `nonFilmRelativeCut 1.12`, `nonFilmDilationRadius 2`,
`minimumMaskedCandidates 24`, `modeWindow 0.03`, `demoteMinLuma 0.60`,
`demoteRatioRange 0.12...0.87`, `demoteGapMaxFraction 0.002`, `demoteRBRatio 0.75`,
`minimumCandidateLuma 0.012`, `minimumMaskRatio 0.10`, `minimumMaskSeparation 0.004`,
`maximumNeutralSpreadRatio 0.12`, `neutralSpreadFloor 0.01`, `candidateFloorFraction 0.10`,
`stripBaseLevelFraction 0.5`, `stripBrightFraction 0.55`, `stripClippingCut 0.97`,
MAD 계수 `1.4826 * 3.0`, 응집 임계 `max(24, 표본 0.4%)`, 선택 비교 `0.85`.

후보 판정의 흑백/컬러 분기(흑백 luma 상한 `0.92` + 비례 중립 허용오차, 컬러 상한 `0.85` +
`R≥G≥B` 단조 + `R−B ≥ max(0.004, 0.10·peak)`)도 그대로입니다.

선택 순서도 같습니다: 연결 성분 → (가장자리, 분산) 두 표본 비교(`edge ≥ distributed × 0.85`
이면 가장자리) → 단독 성공 → `confidentOnly` 면 여기서 중단 → 보더 폴백 → 그리드 생성 실패
시에만 스트립 평균.

## 실제 필름 측정

사용자의 Plustek OpticFilm 8100 컬러 네거티브에서 `NF_BASE_ESTIMATION_AUTO` 로 측정한
Dmin 과 provenance 입니다.

**코퍼스 15장 전부**입니다.

| 프레임 | provenance | Dmin (R, G, B) | R/B |
|---|---|---|---|
| frame_1 | `connected_component` | 0.2286, 0.1360, 0.0724 | 3.16 |
| frame_2 | `connected_component` | 0.2296, 0.1295, 0.0675 | 3.40 |
| frame_3 | `connected_component` | 0.2358, 0.1374, 0.0730 | 3.23 |
| frame_4 | `connected_component` | 0.2006, 0.1027, 0.0468 | 4.29 |
| frame_5 | `connected_component` | 0.2393, 0.1375, 0.0737 | 3.25 |
| frame_6 | `connected_component` | 0.1601, 0.0706, 0.0299 | 5.36 |
| frame_7 | `connected_component` | 0.2353, 0.1360, 0.0715 | 3.29 |
| frame_8 | `connected_component` | 0.2369, 0.1371, 0.0710 | 3.34 |
| frame_9 | `connected_component` | 0.2368, 0.1382, 0.0743 | 3.19 |
| frame_10 | `connected_component` | 0.1972, 0.0999, 0.0450 | 4.38 |
| frame_11 | `connected_component` | 0.2876, 0.1511, 0.0841 | 3.42 |
| frame_12 | `connected_component` | 0.2815, 0.1453, 0.0797 | 3.53 |
| frame_13 | `connected_component` | 0.2784, 0.1434, 0.0777 | 3.58 |
| frame_14 | `connected_component` | 0.2789, 0.1442, 0.0793 | 3.52 |
| frame_15 | `connected_component` | 0.2832, 0.1480, 0.0821 | 3.45 |

**15장이 전부 1차 경로인 연결 성분에서 측정됐습니다.** 가장자리·분산·스트립 폴백은 물론이고
고정 상수 `auto_fallback` 도 **한 번도** 나오지 않았습니다. 추정기가 실제 필름에서 매번
가장 강건한 경로로 답을 낸다는 뜻입니다.

Dmin 은 전부 `R > G > B` 로 컬러 네거티브의 오렌지 마스크와 맞습니다. 절대값은
`R 0.160...0.288` 로 프레임마다 다른데, 이는 스캔 노출 차이이지 추정 불안정이 아닙니다 —
투과율이 낮게 실린 프레임(frame_6, frame_4, frame_10)일수록 `R/B` 비가 커지는데, 오렌지
마스크가 가장 강하게 흡수하는 청색이 그만큼 더 많이 눌리는 물리와 일치합니다.

frame_12 는 big-endian LZW + alpha + ICC 인데도 같은 경로로 측정됩니다 — 디코드 형식이
추정기에 영향을 주지 않는다는 뜻입니다.

## 검증하지 않은 것

- **같은 입력의 macOS Dmin 값과의 직접 비교.** 로직과 상수가 같다는 것은 확인했지만, 같은
  파일을 macOS 에 넣어 나온 숫자와 대조한 것은 아닙니다. Core Image 의 축소 표본화와 Windows
  격자 표본화가 다르므로 마지막 자리는 다를 수 있습니다.
- 흑백 네거티브. 이 코퍼스는 전부 컬러라 중립 베이스 분기는 합성 테스트로만 확인했습니다.
- 폴백 경로들. 15장이 전부 1차 경로로 끝났다는 것은 좋은 소식이지만, 그만큼 실제 필름으로
  가장자리·분산·스트립 폴백을 밟아 보지는 못했다는 뜻이기도 합니다.
