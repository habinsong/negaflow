# 남은 일 전부 — 2026-08-16

이 문서 하나만 읽으면 무엇이 남았는지 알 수 있게 적습니다. 추측은 넣지 않고, 잰 것과 안 잰
것을 나눠 적습니다. **안 잰 것을 "아마 될 것" 으로 적지 않습니다.**

---

## 1. macOS 픽셀 골든 — 여덟 조건 중 다섯이 닫혔습니다

`GT-X900_frame_4.tiff`, macOS 골든 대비 median 차이(16비트). CIVibrance 표를 넣은 뒤의
실측입니다.

| 조건 | R | G | B | 판정 |
| --- | ---: | ---: | ---: | --- |
| a-default-main-srgb | **+16** | +55 | +64 | ✅ 닫힘 |
| d-main-displayp3 | **+23** | +54 | +60 | ✅ 닫힘 |
| d-main-adobergb | **+21** | +50 | +58 | ✅ 닫힘 |
| c-target-f135-srgb | **+26** | +40 | +41 | ✅ 닫힘 |
| c-target-hr-srgb | **+13** | +75 | +93 | ✅ 닫힘 |
| **b-main-scannerprofile-portra400** | **−876** | −616 | −550 | ❌ |
| **c-target-hs-srgb** | **−1025** | −158 | −1180 | ❌ |
| **c-target-sp-srgb** | **−1048** | −573 | −1459 | ❌ |

닫힌 다섯은 8비트로 0.06 ~ 0.36 레벨입니다. 8100 프레임도 여섯 지점이 정확히 일치합니다
(R min 58, G min 71, B max 62256).

### 남은 셋의 성격 — 명부가 눌립니다

median 만 보면 안 됩니다. **max 가 훨씬 크게 어긋납니다.**

| 조건 | Windows max | macOS max | 차이 |
| --- | ---: | ---: | ---: |
| c-target-hs R | 53889 | 59268 | **−5379** |
| c-target-hs G | 51474 | 59166 | **−7692** |
| c-target-sp G | 49907 | 55497 | **−5590** |
| b-scannerprofile B | 62905 | 63001 | −96 |

`c-target-hs` 와 `c-target-sp` 는 **명부가 통째로 눌려 있습니다**. G max 가 7692 낮다는 것은
중간 계조가 아니라 곡선의 어깨가 다르다는 뜻입니다. 반면 `b-scannerprofile` 은 max 가 거의
맞고 median 만 낮으므로 다른 문제입니다 — 곡선 전체가 아니라 위치가 밀려 있습니다.

**중요:** F135 와 HR 은 같은 `ScannerTargetGrade` 경로인데 맞습니다. 그러므로 경로 자체가
아니라 **HS(Noritsu)·SP-3000 두 타깃의 데이터나 계수**가 다릅니다.

### 이건 맥이 없어도 됩니다

골든 통계(`docs/verification/macos-golden/task1-pixels/pixel-stats.json`)가 이미 저장소에
있고, 원본도 있습니다. Windows 쪽 `scanner_target_grade.cpp` 와 `scanner_profile_grade.cpp`
를 macOS 원본과 대조하면 됩니다. **다음에 할 일 중 가장 값이 큽니다.**

---

## 2. macOS 골든 — 5차 요청의 방출 결과

`docs/verification/macos-golden/REQUEST-5.md` 의 macOS 전용 요청은 아래처럼 방출했습니다.
각 산출물의 `manifest.json` 에 입력 SHA-256·렌더 형식·필터 파라미터·출력 SHA-256이 있으며,
실입력 TIFF는 Git LFS로 함께 추적합니다.

| 항목 | 결과 |
| --- | --- |
| **ColorModel vibrance 범위 (−0.8…+0.8)** | `vibrance/civibrance33-am0.800…a0.800-256x141.f32` 일곱 판을 추가했습니다. 양수 0.05…0.50 기존 열한 판은 그대로 둡니다. |
| **채도 낮은 다른 컬러 네거티브** | 아직 없습니다. 새 원본이 없으므로 `GT-X900_frame_4` 이외의 실사진 vibrance 검증이라고 쓰지 않습니다. |
| **CIUnsharpMask 사상** | `task7-coreimage-filters/`에 256² RGBAf 시험 무늬와 clarity·출력 선명화 앵커 여섯 출력을 기록했습니다. 연속 슬라이더 구간은 매니페스트의 정확한 파라미터 식으로 함께 남겼습니다. |
| **CIGaussianBlur 사상** | 같은 시험 무늬에 반경 1.0, 1.3, 2.4, 4.0, 7.0, 10.0을 기록했습니다. |
| **DigitalFilmLook 픽셀 골든** | `task8-digital-film-look/`에 합성 positive 장면의 Portra 400·Velvia 50·Tri-X 400, 강도 0.5/1.0 여섯 출력을 기록했습니다. 필름 스캔 현상 골든으로 오인하면 안 됩니다. |
| **흑백·슬라이드 골든** | `task9-bw-slide/`에 실제 16-bit TIFF 원본과 출력·통계를 모두 넣었습니다. 원본 TIFF에 현상액/필름 화학 정보가 없으므로 D-76 또는 E-6 실측이라고 부르지 않고, 각각 `bwNegative`·`colorPositive` 경로 골든으로 한정합니다. 흑백은 호환 스캐너 프로파일이 없어 b) 조건을 만들지 않았습니다. |

---

## 3. alpha — 전 계층이 비어 있습니다

macOS 는 `ExportOptions.preserveAlpha` 가 있습니다(기본 false).

| 계층 | macOS | Windows |
| --- | --- | --- |
| 옵션 | `preserveAlpha: Bool` | **없음** |
| 거절 규칙 | JPEG + alpha → `unsupportedAlpha`, rawScanTIFF + alpha → 거절 | 없음 |
| 렌더 | true 면 RGBA 유지, false 면 `noneSkipLast` 로 표시 | 언제나 불투명 RGB |
| 작업 이미지 | CIImage 가 알파를 가집니다 | `Rgba32F` 에 alpha 필드는 있으나 `working_to_srgb16` 이 alpha ≠ 1 을 **거절**합니다 |
| UI | 출력 패널 토글 | 없음 |
| 사이드카 | `Sidecar` 에 기록 | 없음 |

**해야 할 일 (전부 Windows 안에서 가능):**

1. `ExportSettings` 에 `PreserveAlpha`, ABI v34 에 `preserve_alpha`
2. `DevelopRequestFactory` 에 거절 규칙 두 가지(JPEG, raw TIFF)
3. `working_to_srgb16` 이 알파를 통과시키는 경로 — 지금은 실패로 처리합니다
4. WIC 로 64bpp/32bpp RGBA 쓰기 + TIFF `ExtraSamples`(338) 허용
5. TIFF 구조 검증이 4 채널을 받도록
6. 출력 패널 토글 + 6개 로케일 문자열(macOS 표에서 생성)
7. 내보내기 프리셋·사이드카에 값 싣기

**주의:** 알파가 실제로 1 미만이 되는 자리가 Windows 에 있는지 먼저 재야 합니다. 기하 변형이
남기는 모서리가 후보입니다. 맥의 채도 프록시에서는 알파 최소가 0.938965 였고 1 미만이 0.41 %
였습니다(맥이 알려준 값). Windows 에서 같은 자리를 재지 않고 구현하면 **쓸 수 없는 토글**을
만드는 것입니다.

---

## 4. 재서 보이지 않아 일부러 안 고친 것

기록해 둡니다. 나중에 "왜 안 고쳤나" 를 다시 묻지 않도록.

| 항목 | 잰 값 | 판단 |
| --- | --- | --- |
| vibrance 앵커만 먼저 고치기 | RMS 707 → 703 | 배율이 지배해서 픽셀만 바뀝니다. 표와 함께 고쳤습니다(끝) |
| 썸네일에서 접는 순서 | 기본 현상은 [0,1] 안이라 항등 | 인화 응답 천장이 0.90 이라 색역 밖이 안 나옵니다 |
| 미리보기 축소를 sRGB 인코딩 공간에서 | 의도된 차이(`develop_export.h` 에 적힘) | 화면 전용, 골든에 안 들어감 |

---

## 5. 이 기계에서 못 하는 것

| 항목 | 이유 |
| --- | --- |
| 순수 ARM64 실행 | 하드웨어가 없습니다. CI 에 cross 잡은 있습니다 |
| 정렬 상관값 실측 | 사용자가 제외한 항목입니다 |

---

## 6. 확인은 됐지만 골든과 태그 단위 대조는 안 한 것

- **메타데이터 정책** — TIFF·JPEG 실파일로 네 정책의 **구성**을 확인했습니다
  (`2026-08-16-export-source-metadata.md`). 다만 macOS task6 골든의 `tiff-tags.json` 과
  **태그 대 태그**로 맞춘 것은 아닙니다. 맥과 같은 고정 픽스처를 Windows 에서 만들어야
  하고, IPTC IIM 을 WIC 로 같은 바이트로 쓰는 것이 남은 부분입니다.

---

## 다음 한 가지를 고른다면

**`c-target-hs` / `c-target-sp` 의 명부입니다.** 맥이 필요 없고, 골든이 이미 있고, G max 가
7692 어긋나 있어 원인이 크고 뚜렷합니다. F135·HR 이 같은 경로에서 맞으므로 범위도 좁습니다.
