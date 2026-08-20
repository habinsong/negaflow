# macOS 저장소 실측 조사

2026-07-31 기준. `negaflow` main 브랜치(80fc71e) 실측.
**2026-08-03 재실측분은 문서 맨 아래 [갱신](#갱신-2026-08-03--9be909c--워킹트리) 절 참조.**

## 규모

| 영역 | 라인 수 | 파일 수 | 이식성 |
|---|---|---|---|
| `Sources/Chromabase` (엔진) | 25,664 | 139 | **71파일은 CoreImage/CoreGraphics/ImageIO/ColorSync import 없음** |
| `Sources/ScannerKit` | 6,736 | 50 | 외부 프로세스 플러그인으로 이미 분리 |
| `Sources/negaflowApp` (GUI) | 75,783 | 517 | **전량 재작성 (공유 0%)** |
| `Sources/negaflowCLI` | 1,074 | 11 | Windows 첫 목표로 적합 |
| `Tests` | 67,933 | 247 | 수치 기대값은 자산, 픽스처 코드는 재작성 |
| **합계** | **177,190** | **964** | `Sources` + `Tests`의 Swift 파일만 집계 |

테스트 함수 이름 패턴은 약 **1,840개**다.

## Apple 프레임워크 결합도

import 하는 파일 수:

| 프레임워크 | 파일 수 |
|---|---|
| Foundation | 506 |
| SwiftUI | 212 |
| CoreImage | 195 |
| CoreGraphics | 190 |
| AppKit | 152 |
| ImageIO | 58 |
| Combine | 40 |
| UniformTypeIdentifiers | 20 |
| Metal | 7 |
| Accelerate | 1 |
| MetalPerformanceShaders / AVFoundation / ImageCaptureCore / CoreML | 0 |

참조 총량:

- `CIImage` — 393곳
- `CGImage` — 475곳
- `CIContext` — 26개 source 파일에서 참조, 그중 10개 파일에 생성 표현

## 결합도가 높은 파일 (Chromabase, CIImage 참조 순)

| 파일 | 참조 |
|---|---|
| `DefectRemoval/SoftwareDefectRemoval.swift` | 27 |
| `Engine/ChromabaseEngine.swift` | 16 |
| `Film/NegativeInversion.swift` | 12 |
| `Export/PrintPackageRenderer.swift` | 11 |
| `DefectRemoval/DefectScratchRepairer.swift` | 11 |
| `Export/PrintComposition.swift` | 10 |
| `DefectRemoval/SoftwareDefectDetector.swift` | 10 |
| `Adjustments/ScannerNoiseReduction.swift` | 10 |
| `Adjustments/LocalDodgeBurnStage.swift` | 9 |
| `Engine/ChromabaseEngine+NegativePipeline.swift` | 8 |

## 순수 수학 파일 (Apple 이미징 import 없음)

전체 71개 중 대표적인 것:

```
DefectRemoval/  DefectDustDetector, DefectScratchDetector, DefectClassifier,
                DefectMorphology, DefectContrastField, DefectShape,
                DefectLabeledMask, DefectParallelAccumulators,
                InfraredDefectRemoval+AlignmentMath, +Alignment, +Spectral,
                ComponentMask/DefectComponentMask, ConcurrentResultStore,
                DefectScratchRepairer+Texture, +Components,
                SoftwareDefectRemoval+GlobalStructure, DefectBenchReferenceMetrics
Film/           FilmType, FilmStockDmin, FilmBaseStatistics,
                FilmBaseMeasurementDiagnostics, LightSourceProfile
Develop/        DevelopParameters, DevelopAdjustments, DevelopToneRange,
                DevelopHistory, DevelopKeyboardNudge
Export/         RenderManifest(+Coding/+Hashing/+Validation), ExportArtifacts,
                ExportEncodingOptions, RenderManifestModels, Sidecar, Sidecar+XMP
Adjustments/    FilmEmulationProfile, FilmEmulationProfile+Slide
```

이 파일들은 Apple image-object 의존이 낮아 우선 이식하기 좋다. 다만 Swift numeric semantics,
정수 overflow, concurrency, Foundation type과 테스트 fixture를 확인해야 하므로 “언어만 바꾸면
동일하다”고 간주하지 않는다.

## 셰이더 자산 — 예상보다 좋음

`Sources/Chromabase/Engine/ChromabaseMetalKernels.swift` — **618줄, stitchable 커널 21개**.

구조: `CIKernel.kernels(withMetalString:)`로 하나의 Metal 소스 문자열을 통째로 컴파일해 이름별 딕셔너리로 보관.

Core Image 전용 문법은 `coreimage::sample_t` **42곳뿐**. 나머지 본문은 표준 Metal 수학이다.

커널 목록은 [../02-shaders/kernel-inventory.md](../02-shaders/kernel-inventory.md) 참조.

## 표준 CIFilter 사용 (적음)

문자열 이름으로 생성하는 것만:

| 필터 | 횟수 |
|---|---|
| `CIBlendWithMask` | 9 |
| `CIRandomGenerator` | 2 |
| `CIMedianFilter` | 2 |
| `CILinearDodgeBlendMode` | 2 |
| `CIVibrance` / `CIScreenBlendMode` / `CIRadialGradient` / `CIMix` / `CIDissolveTransition` / `CIAreaAverage` | 각 1 |

추가로 `applyingFilter("CIColorMatrix", ...)` 형태 사용.

→ **내장 필터 의존이 얕다.** 대부분이 자체 커널이라 이식 시 유리하다.

## 색공간 사용

| 표현 | 횟수 |
|---|---|
| `CGColorSpace.linearSRGB` | 48 + 2 |
| `CGColorSpace.sRGB` | 44 + 1 |
| `CGColorSpace.extendedLinearSRGB` | 4 |
| `ColorSyncProfile` | 4 |
| `CGColorSpace(iccData:)` | 3 |
| `CGColorSpace.genericRGBLinear` | 2 |
| `genericLab` / `displayP3` / `adobeRGB` | 각 1 |

`extendedLinearSRGB` → Windows는 **DXGI scRGB**가 대응 ([../04-color-management/color-pipeline.md](../04-color-management/color-pipeline.md)).

## 통계·렌더 지점 (플랫폼 종속 핵심)

`CIAreaAverage` / `CIAreaHistogram` / `render(` / `createCGImage` 를 쓰는 파일 20여 개:

```
Engine/ChromabaseEngine+NegativePipeline    Develop/AutoLevels
Export/ExportRenderedImage                  Export/ExportEngine
Export/DestinationGamutWarning              Imaging/PixelSampler
DefectRemoval/DefectHealBrush               DefectRemoval/SoftwareDefectRemoval
DefectRemoval/SoftwareDefectDetector        DefectRemoval/DefectScratchRepairer
DefectRemoval/DefectBenchArtifacts          DefectRemoval/InfraredDefectRemoval+Planes
Profiles/ColorTarget/ScannerRelativeIT8Benchmark
Profiles/ColorTarget/IT8PatchEvaluator
Film/NegativeInversion                      Film/FilmBaseSampleGrid
Film/FilmBasePicker                         Film/FilmBaseEstimator
Adjustments/ToneMapper                      Adjustments/NeutralBalance
```

**여기가 급소다.** 톤 파이프라인이 측정값에 의존하는데, 그 측정이 Apple 구현에 묶여 있다. → [../03-measurement/histogram-and-statistics.md](../03-measurement/histogram-and-statistics.md)

## 데이터 자산 (그대로 복사 가능)

```
Sources/Chromabase/ScannerProfiles/
    manifest.json
    noritsu__color-nega__{fuji-c200, kodak-ektar-100, kodak-portra-160,
                          kodak-portra-400, kodak-portra-800,
                          kodak-pro-image-100, kodak-ultramax-400,
                          kodak-vision3-250d, kodak-vision3-50d}.json
    noritsu__color-slide__{kodak-ektachrome-100, kodak-ektachrome-100d}.json
    sp-3000__color-nega__{kodak-ektar-100, kodak-portra-160,
                          kodak-vision3-250d}.json
    sp-3000__color-slide__kodak-ektachrome-100d.json

Sources/Chromabase/Presets/
    neutral.json  rich-neutral.json  soft-print.json
    warm-lab.json  clear-chrome.json  deep-slide.json

LUT_target/
    PROFILES/  REAL/  SOURCE/  TARGET/
    analyze_lut_target.py
    compile_scanner_profiles.py
    validate_scanner_profiles.py
```

## GUI 기능 구성 (재작성 대상)

`Sources/negaflowApp/Features/`:

```
Canvas  Defects  Develop  Export  Help  Library  Print  Scanning  Versions  Workspace
```

큰 파일:

| 파일 | 라인 |
|---|---|
| `Features/Export/ExportArtifactCommitJournal.swift` | 1,304 |
| `Features/Print/PrintPackageInspectorControls.swift` | 791 |
| `Features/Scanning/ScanSection.swift` | 684 |
| `Localization/Phrases/Tables/*` (6개 언어) | 각 ~605 |
| `Services/Storage/Catalog/SQLite/LibraryCatalogSQLiteStore.swift` | 601 |

다국어 6개(en/ko/ja/de/fr/zh-Hans) 문자열 테이블은 **번역 자산으로 그대로 이관 가능**하다.

---

## 갱신 2026-08-03 (`9be909c` + 워킹트리)

측정 방식은 최초 조사와 동일하게 맞췄다(import 파일 수는 `Sources` + `Tests` 합산).

### 규모 변화

| 영역 | 07-31 | 08-03 | 증감 |
|---|---|---|---|
| `Sources/Chromabase` | 25,664줄 / 139파일 | **27,107줄 / 147파일** | +1,443 / +8 |
| `Sources/ScannerKit` | 6,736 | 6,736 | — |
| `Sources/negaflowApp` | 75,783 | 75,913 | +130 |
| `Sources/negaflowCLI` | 1,074 | 1,074 | — |
| `Tests` | 67,933 / 247파일 | **68,790 / 249파일** | +857 / +2 |
| **합계** | 177,190 / 964 | **179,620 / 974** | +2,430 / +10 |
| 테스트 함수 이름 패턴 | ~1,840 | **~1,878** | +38 |

두 시점 모두 `git archive`의 `Sources` + `Tests` 안에서 `.swift` 파일과 newline bytes를
같은 방식으로 집계했다. 테스트 함수 수는 `func test...` 이름 패턴이므로 XCTest가 동적으로
생성하는 case 수와 같다는 뜻은 아니다.

증가분의 큰 부분은 **디지털 소스 가상 현상**이다:
`Sources/Chromabase/Digital/` 8파일 1,184줄 + `Tests/…/DigitalFilmLookTests.swift` 618줄.
→ [../15-digital-film/virtual-development.md](../15-digital-film/virtual-development.md)

### Chromabase 내부 분포 (신규 측정)

| 하위 폴더 | 줄 수 | Windows 이식 성격 |
|---|---|---|
| `Profiles/` | 6,108 | 스캐너 프로파일·IT8. **데이터 + 순수 수학** |
| `DefectRemoval/` | 5,893 | **CPU 집약. 이식 난이도 최상** → [CPU SIMD·dispatch](../16-cpu/simd-and-dispatch.md) |
| `Export/` | 3,985 | ImageIO 의존 → libtiff/WIC |
| `Imaging/` | 2,676 | 로더·픽셀 샘플러 |
| `Adjustments/` | 2,617 | 톤·색. 대부분 커널 인자 계산 |
| `Film/` | 1,903 | 반전·필름 베이스. **파이프라인의 심장** |
| `Engine/` | 1,648 | 파이프라인 조립 + 커널 소스 |
| `Digital/` | **1,184** | 신규. 디지털 소스 전용 |
| `Develop/` | 1,093 | 파라미터 모델. 순수 |

### 프레임워크 결합도 (재측정)

| 프레임워크 | 07-31 | 08-03 |
|---|---|---|
| Foundation | 506 | 508 |
| SwiftUI | 212 | 212 |
| CoreImage | 195 | **202** |
| CoreGraphics | 190 | 197 |
| AppKit | 152 | 152 |
| ImageIO | 58 | 59 |
| Combine | 40 | 40 |
| Metal | 7 | 7 |
| **Accelerate** | **1** | **1** |

**Accelerate가 1파일에 머물러 있다는 게 이번 재측정의 가장 좋은 소식이다.**
그 1파일(`DefectMorphology.swift`)조차 vImage 없이 도는 동등 구현을 이미 갖고 있다.
→ [../16-cpu/accelerate-replacement.md](../16-cpu/accelerate-replacement.md)

같은 `Sources/**/*.swift` literal count에서 `CIImage`는 393 → 423, `CGImage`는
475 → 475다. 이 수치는 결합도 방향을 찾기 위한 검색 지표이며 API call 수나 이식 공수와 같지 않다.

### 셰이더 자산 재측정

```
ChromabaseMetalKernels.swift   618줄 → 814줄
[[stitchable]] 커널            21개 → 31개
coreimage::sample_t            42곳 → 56곳
destination/sampler/texture2d  0 → 0     ← 유지
```

**포인트와이즈 성질이 깨지지 않았다.** 커널이 10개 늘어도 이웃 픽셀을 직접 읽는 커널이
하나도 생기지 않았다 → Direct2D `D2D_INPUT_SIMPLE` + shader linking 전제를 계속 밀 수 있다.

### 이 갱신이 이식 계획에 주는 영향

| 항목 | 판단 |
|---|---|
| 커널 10개 추가 | 일정 증가. 단 **맨 뒤 순위** — 필름 경로 수치가 맞은 뒤 |
| PNG 16bit / JPEG 품질 기본 1.0 | 내보내기 사양 갱신 → [../05-image-io/export-formats.md](../05-image-io/export-formats.md) |
| 나머지 구조 | **변경 없음.** 기존 문서의 전제가 여전히 유효하다 |
