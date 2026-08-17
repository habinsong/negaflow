# 08 — macOS 에 있고 Windows 에 없는 백엔드

2026-08-17. macOS `Sources/Chromabase` + `Sources/negaflowApp` 을 Windows `src/Native` +
`src/Shell.Core` + `src/Catalog.Core` + `src/Interop` 와 대조한 결과입니다.

**방법**: macOS 파일 이름을 개념 키워드로 바꿔 Windows 전 트리를 `grep -rl` 로 훑었습니다.
**히트 0 = 그 개념이 Windows 코드베이스에 한 글자도 없음**입니다. 히트가 있어도 이름만 같고
내용이 다를 수 있으므로, 아래 표의 "있음" 은 **이식 완료를 뜻하지 않습니다.**

## 0. 규모

| | 파일 | 줄 |
|---|---:|---:|
| macOS `Chromabase` (엔진) | 159 | 30,556 |
| Windows `src/Native` | 286 | 58,875 |

**줄 수가 두 배라고 이식이 끝난 것이 아닙니다.** 아래가 실제 격차입니다.

---

## 1. 완전히 없음 — 히트 0

가장 중요한 목록입니다. 이름조차 없습니다.

### 1.1 스캐너 색 프로파일링 / IT8 (macOS 8개 파일, 약 2,500줄)

| macOS 파일 | 하는 일 |
|---|---|
| `Profiles/IT8Reference.swift` | IT8 타깃 참조값 |
| `Profiles/IT8PatchEvaluator.swift` | 패치 측정·평가 |
| `Profiles/IT8BenchmarkModels.swift` | 벤치마크 모델 |
| `Profiles/ScannerRelativeIT8Benchmark.swift` | 스캐너 상대 IT8 벤치 |
| `Profiles/ScannerRelativeIT8BenchmarkModels.swift` | 〃 모델 |
| `Profiles/ColorTargetColorimetry.swift` | 컬러 타깃 측색 |
| `Profiles/MonotoneCubic.swift` | 단조 3차 보간 |
| `Profiles/LookPreset.swift` (부분) | — |

**`MonotoneCubic` 이 없는 것이 특히 위험합니다.** 톤 곡선·LUT 보간의 기본 도구인데 Windows
전 트리에 한 글자도 없습니다. Windows 가 다른 보간을 쓰고 있다면 **곡선 모양이 macOS 와
다릅니다** — 슬라이더를 같은 값으로 놔도 결과가 달라집니다.

### 1.2 현상 파이프라인

| macOS 파일 | 하는 일 | Windows |
|---|---|---|
| `Film/PositiveDevelop.swift` | **포지티브(슬라이드) 현상 경로** | **없음** |
| `Digital/DigitalSceneReconstruct.swift` | 디지털 소스 장면 재구성 | **없음** |
| `Imaging/ChannelClippingOverlay.swift` | 채널 클리핑 표시 | **없음** |

`PositiveDevelop` 이 없다는 것은 **슬라이드 필름 현상 경로가 통째로 없다**는 뜻입니다.
확인하십시오 — 필름 종류에 포지티브가 있는데 경로가 없으면 그 선택지는 가짜입니다.

### 1.3 내보내기

| macOS 파일 | 하는 일 | Windows |
|---|---|---|
| `Export/RenderManifest.swift` (+Coding/+Hashing/+Validation/Models, 5개) | **렌더 매니페스트** — 무엇을 어떤 설정으로 냈는지 기록·해시·검증 | **없음** |
| `Export/DestinationGamutWarning.swift` | 대상 색역 벗어남 경고 | **없음** |
| `Export/ICCOutputProfileSnapshot.swift` | 출력 ICC 스냅샷 | **없음** |
| `Export/Sidecar+XMP.swift`, `Sidecar+ExportMetadataXMP.swift` | XMP 사이드카 | **거의 없음**(히트 2) |

### 1.4 GrainMend 내부

| macOS 파일 | Windows |
|---|---|
| `DefectRemoval/DefectStructureLineFilter.swift` | **없음** |
| `DefectRemoval/DefectScratchResponseMap.swift` | **없음** |
| `DefectRemoval/SoftwareDefectRemoval+GlobalStructure.swift` | **없음** |
| `DefectRemoval/DefectBench*.swift` (4개) | **없음** (벤치 도구) |

`ScratchResponseMap` + `GlobalStructure` 는 **타일 봉합 후 프레임 전체에서 구조선을
재판정**하는 짝입니다. Windows 는 `build_automatic_mask_from_evidence` 안에서 비슷한 일을
하지만 **파일 대조를 하지 않았습니다.** 오탐지 억제의 핵심이라 반드시 대조해야 합니다.

### 1.5 라이브러리 백엔드

| macOS 파일 | 하는 일 | Windows |
|---|---|---|
| `Library/Model/AppModel+SupportBundle.swift` | 지원 번들(진단 묶음) 생성 | **없음** |
| `Library/Model/AppModel+LibraryArchive.swift` | 라이브러리 보관 | **없음** |
| `Library/Model/AppModel+LibraryManualBackup.swift` | 수동 백업 | **없음** |
| `Library/Model/AppModel+PhotoNumbering.swift` | **사진 번호 매기기** | **없음** |
| `Library/Model/AppModel+ScanProvenanceProtection.swift` | 스캔 출처 보호 | **없음** |
| `Library/Model/Collections/LibraryOrganizerProjection.swift` | 조직자 투영 | **없음** |
| `Library/Duplicates/*.swift` (4개) | 중복 후보 스캔·시트 | **거의 없음**(히트 1) |

**`PhotoNumbering` 이 없는 것이 상단 바 문제와 직결됩니다** — macOS 상단 중앙은 `사진 1`
이라는 **사진 번호**를 냅니다(07 문서 1.3). Windows 가 파일명을 내는 이유가 이것입니다.
번호 체계 자체가 없습니다.

---

## 2. 이름은 있으나 대조 안 함 — 히트는 있음

"있음" 으로 적으면 안 되는 것들입니다. 히트 수만으로는 **껍데기인지 구현인지 모릅니다.**

| macOS | 히트 | 확인할 것 |
|---|---:|---|
| `Adjustments/ScannerNoiseReduction*.swift` (3개) + `Profiles/ScannerNoiseProfile*.swift` (4개) | 21 | 7개 파일 분량이 실제로 있는가. 프로파일 측정·선택·검증 3단계가 다 있는가 |
| `Adjustments/NeutralBalance.swift` | 15 | |
| `Adjustments/OutputDither.swift` | 12 | |
| `Develop/AutoLevels.swift` | 21 | |
| `Film/FilmBaseEstimator/Picker/SampleGrid/Statistics/MeasurementDiagnostics` (5개) | 4 | **5개 파일에 히트가 4곳뿐**. 베이스 추정·샘플 격자·통계·진단이 다 있는가 |
| `Film/LightSourceProfile.swift` | 19 | |
| `Film/PrintPaperGrade.swift` | 4 | 히트 4곳이 전부 인화 UI 쪽. **엔진 쪽 등급 계산이 있는가** |
| `Export/SoftProof.swift` | 28 | |
| `Export/OutputSharpening.swift` | 23 | |
| `Export/PrintPackage*.swift` (4개) | 9 | |
| `Develop/DevelopHistory.swift` | 0* | 별도 이름일 수 있음 — undo 스택이 없다는 03 문서와 일치 |
| `Develop/DevelopKeyboardNudge.swift` | 0* | 인스펙터 키보드 이동(04 문서 4.6) |
| `Develop/DevelopUserPreset.swift` | 0* | 프리셋 저장 |
| `Profiles/ScannerTargetGrade*.swift` (7개) | 2 | **7개 파일에 히트 2곳.** 색 큐브·색 수학·문서화된 특성·포지티브 시그니처·텍스처 5개 갈래가 있는가 |
| `Profiles/ScannerProfileGrade/Matcher/Registry/Models` (5개) | 2 | 같은 문제 |

\* 파일명 키워드 히트 0. 개념이 다른 이름으로 있을 수 있으므로 **확인 후 판정**.

---

## 3. 대조 완료 — 차이 없음

- `DefectComponentMask+Components.gridLineDrops` ↔ `structure_grid_drops`:
  두 메커니즘·보조 함수·**상수 12개 전부 일치**(01 문서 1.4)
- `DefectShape` ↔ `grain_mend_shape`
- `DefectClassifier` ↔ `grain_mend_classifier`
- `SoftwareDefectDetector.maxDetectDim = 1800` ↔ `grain_mend_maximum_detection_dimension`

---

## 4. 확인 순서

격차 크기와 사용자 체감 순입니다.

1. **`MonotoneCubic`** — 톤 곡선 보간. 없으면 모든 곡선 결과가 macOS 와 다릅니다.
   가장 작고 가장 널리 퍼지는 영향입니다
2. **`PositiveDevelop`** — 슬라이드 현상 경로. 없으면 그 필름 종류가 가짜입니다
3. **`AppModel+PhotoNumbering`** — 상단 바가 파일명을 내는 이유
4. **`ScratchResponseMap` + `GlobalStructure`** — 오탐지 억제의 핵심
5. **`ScannerTargetGrade` 7개 / `ScannerProfileGrade` 5개** — 히트 2곳뿐. 스캐너 색 보정의
   본체입니다
6. **`FilmBase*` 5개** — 히트 4곳. 필름 베이스 추정이 실제로 도는지
7. **IT8 8개** — 스캐너 프로파일링 전체
8. **`RenderManifest` 5개** — 내보낸 것의 기록·검증
9. **라이브러리 백엔드 7개** — 지원 번들·보관·백업·출처 보호·조직자·중복
10. **`DestinationGamutWarning` / `ICCOutputProfileSnapshot` / XMP 사이드카**

## 5. 확인 방법

```bash
# 개념이 있는지
grep -rl "<키워드>" --include=*.cpp --include=*.h --include=*.cs src/

# 있으면 macOS 원문과 나란히 놓고 함수·상수 단위로 대조
```

**"히트가 있으니 있음" 으로 적지 마십시오.** 이번 세션에 검출기가 "오케스트레이션은 있음"
으로 적혀 있었지만 실제로는 macOS 의 **브러시 경로**를 자동에 쓰고 있었습니다. 파일이 있고
이름이 같아도 **다른 것을 하고 있을 수 있습니다.**

각 항목을 확인할 때마다 이 문서의 판정을 갱신하십시오:
**없음** / **껍데기**(있으나 안 씀) / **다름**(하는 일이 다름) / **같음**(함수·상수 대조 완료).
