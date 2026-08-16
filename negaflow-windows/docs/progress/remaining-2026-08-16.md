# 남은 일 전부 — 2026-08-16

이 문서 하나만 읽으면 무엇이 남았는지 알 수 있게 적습니다. 추측은 넣지 않고, 잰 것과 안 잰
것을 나눠 적습니다. **안 잰 것을 "아마 될 것" 으로 적지 않습니다.**

---

## 1. macOS 픽셀 골든 — Task 1 원본이 현재 저장소에 없습니다

아래 표는 `GT-X900_frame_4.tiff`가 작업 트리에 있던 때의 마지막 측정입니다. 현재 golden 출력과
통계는 받았지만 원본 TIFF는 저장소에 없으므로, 2026-08-16 이후의 `ScannerTargetGrade` 끝점 보정을
같은 실제 입력으로 다시 검증할 수 없습니다.

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

### 원본이 들어오면 맥 없이 할 수 있습니다

golden 통계(`docs/verification/macos-golden/task1-pixels/pixel-stats.json`)와 출력은 저장소에
있습니다. `GT-X900_frame_4.tiff` 원본이 제공되면 Windows 쪽
`scanner_target_grade.cpp`·`scanner_profile_grade.cpp`를 실제 ABI 경로로 다시 비교합니다.

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

## 3. alpha — Windows 전 계층 구현·검증 완료

macOS 는 `ExportOptions.preserveAlpha` 가 있습니다(기본 false).

`preserve_alpha`는 ABI v34, Shell 설정·사이드카·여섯 로케일, PNG/TIFF 8·16bit WIC 경로와
TIFF `ExtraSamples`(338) 구조 검증까지 연결했습니다. JPEG와 raw scanner TIFF는 macOS 계약대로
거절합니다. x64 Debug에서 alpha 보존 PNG/TIFF, RGB 경로, ABI export와 managed test를 확인했습니다.
alpha의 실제 macOS 픽셀 golden은 Windows에서 다시 만들 수 없으므로, 이 결과는 Windows
구조·왕복 검증이지 macOS pixel-exact 주장에는 쓰지 않습니다.

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
| Task 1 실제 재렌더 | golden 출력은 있으나 `GT-X900_frame_4.tiff` 원본이 저장소에 없습니다 |

---

## 6. golden을 받은 뒤 Windows에서 실행한 것

- **CIVibrance** — 음수·양수 17개 macOS RGBAf plane을 `native.color_model`에 연결했습니다.
  표는 특정 사진 분기가 아니라 33³ 전체 입력의 일반 response 사상입니다.
- **Task 7** — CIUnsharpMask/CIGaussianBlur 10개 RGBAf fixture를 `native.texture_stage`에
  연결했습니다. 최대 절대 차이 상한은 0.008이며, CI 경계 표본 방식 때문에 exact 판정은 아닙니다.
- **Task 8** — Digital Film Look 6개 RGBAf fixture를 `native.working_film_look`에 연결했습니다.
  최대 관측 차이는 0.004713 미만, 회귀 상한은 0.005입니다.
- **Task 9** — 실제 16-bit TIFF 15개를 Windows ABI v32 export로 다시 썼습니다. color-positive
  8개는 RGB16 중앙값 절대 차이 32 이하를 자동 검증합니다. B&W 7개는 +1,089…+1,909 중앙값
  밝기 차이가 남아 아직 수치 pass 기준으로 고정하지 않았습니다.

전체 명령과 수치·경계는
`../verification/2026-08-16-request-5-windows-golden.md`에 기록했습니다.

---

## 7. 확인은 됐지만 golden 파일과 바이트 단위 대조는 안 한 것

- **메타데이터 정책** — TIFF·JPEG 실파일로 네 정책의 **구성**을 확인했습니다
  (`2026-08-16-export-source-metadata.md`). 다만 macOS task6 골든의 `tiff-tags.json` 과
  **태그 대 태그**로 맞춘 것은 아닙니다. 맥과 같은 고정 픽스처를 Windows 에서 만들어야
  하고, IPTC IIM 을 WIC 로 같은 바이트로 쓰는 것이 남은 부분입니다.

---

## 다음 한 가지를 고른다면

**Task 1 원본 TIFF를 받는 일입니다.** 그 다음 `c-target-hs`/`c-target-sp`의 명부를 실제 출력으로
재현할 수 있습니다. B&W Task 9는 그 다음이며, macOS intermediate 진단값 또는 pre-inversion
golden이 있어야 일반적인 원인을 좁힐 수 있습니다.
