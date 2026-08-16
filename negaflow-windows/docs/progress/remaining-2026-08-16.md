# 남은 일 전부 — 2026-08-16

이 문서 하나만 읽으면 무엇이 남았는지 알 수 있게 적습니다. 추측은 넣지 않고, 잰 것과 안 잰
것을 나눠 적습니다. **안 잰 것을 "아마 될 것" 으로 적지 않습니다.**

---

## 1. macOS 픽셀 골든 — Task 1 실제 ABI 재렌더 완료

사용자가 제공한 저장소 밖 `GT-X900_frame_4.tiff`를 사용했습니다. 파일은 golden manifest의
SHA-256 `9e3d0daf…d1a198` 및 47,316,912 bytes와 일치합니다. Windows ABI v32 export가 원본과
여덟 macOS 출력 TIFF의 SHA-256을 먼저 확인한 뒤 다시 TIFF16을 만들고 WIC RGB16으로 비교합니다.
원본은 제품·테스트에 경로로 고정하거나 저장소에 복사하지 않습니다.

| 조건 | R | G | B | 판정 |
| --- | ---: | ---: | ---: | --- |
| a-default-main-srgb | +13 | +49 | +56 | 중앙값 회귀 통과 |
| b-main-scannerprofile-portra400-srgb | −18 | +9 | +6 | 중앙값 회귀 통과 |
| c-target-hs-srgb | +23 | +48 | +63 | 중앙값 회귀 통과 |
| c-target-sp-srgb | +15 | +85 | +55 | 중앙값 회귀 통과 |
| c-target-f135-srgb | +16 | +43 | +49 | 중앙값 회귀 통과 |
| c-target-hr-srgb | 0 | +53 | +54 | 중앙값 회귀 통과 |
| d-main-displayp3 | +20 | +49 | +55 | 중앙값 회귀 통과 |
| d-main-adobergb | +19 | +45 | +51 | 중앙값 회귀 통과 |

수치는 RGB16 channel median 차이이며 자동 회귀 한계는 채널별 절대값 96 코드(8-bit 0.4 레벨)입니다.
Portra 400의 이전 중앙값 밀림은 Windows가 `CIToneCurve`를 선형광에 직접 적용한 결함이었습니다.
macOS 계약의 감마 2 지각 공간 spline으로 바꿔 해결했습니다.

### 아직 pixel-exact는 아닙니다

중앙값 회귀는 여덟 조건 모두 통과했지만, 국소 최대 절대 차이는 Portra 400에서
R/G/B `5677/6482/5705`, HS에서 `4478/3102/3061`, SP에서 `2954/2601/3921` RGB16 코드입니다.
따라서 이 결과를 전 픽셀 동등성으로 해석하지 않습니다. 남은 국소 차이는 macOS의 비공개
neighborhood/color-filter 구현과 Windows CPU 근사의 차이로만 기록하며, 제품 코드에 입력별
보정값을 넣지 않습니다.

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

---

## 6. golden을 받은 뒤 Windows에서 실행한 것

- **CIVibrance** — 음수·양수 17개 macOS RGBAf plane을 `native.color_model`에 연결했습니다.
  표는 특정 사진 분기가 아니라 33³ 전체 입력의 일반 response 사상입니다.
- **Task 6** — macOS `policy-all.tif`를 실제 source로 하여 Windows TIFF 네 정책을 다시
  만들고, root IFD의 Artist/Copyright/ImageDescription 문자열 값과 EXIF·IPTC·GPS 블록
  보존/제거를 `native.task6_metadata_golden`에서 확인합니다. 태그 순서·IPTC IIM 바이트열의
  동일성은 이 검증 범위가 아닙니다.
- **Task 7** — `native.texture_stage`가 CIUnsharpMask 6개와 clarity 양수 3개, 음수 2개(반경
  7·10) RGBAf fixture를 실제 stage 출력으로 비교합니다. 추가로 공통 `CIGaussianBlur` 반경
  사상은 1.0·1.3·2.4·4.0·7.0·10.0 여섯 fixture 전체를 직접 비교합니다. 이 사상은
  `sigma² = radius² + 0.08`, ±3σ support이며, 실제 1.0 heal-brush와 1.3 FilmScanDenoise도
  같은 함수를 사용합니다. 최대 절대 차이 상한은 0.008이며 CI 경계 표본 방식 때문에 exact
  판정은 아닙니다. 2.4는 현재 macOS `ScannerNoiseReduction` 정의에는 있으나 제품 호출 경로가
  없어 Windows에 비노출 기능을 임의로 추가하지 않았습니다.
- **Task 8** — Digital Film Look 6개 RGBAf fixture를 `native.working_film_look`에 연결했습니다.
  최대 관측 차이는 0.004713 미만, 회귀 상한은 0.005입니다.
- **Task 9** — 실제 16-bit TIFF 15개를 Windows ABI v32 export로 다시 썼습니다. color-positive
  8개는 RGB16 중앙값 절대 차이 32 이하, B&W 7개는 64 이하를 자동 검증합니다. B&W 자동 base가
  측정 실패 뒤 크로모제닉 재시도를 건너뛰던 Windows 제어 흐름을 고쳐, 중앙값 차이는
  0…−56 코드까지 줄었습니다.

전체 명령과 수치·경계는
`../verification/2026-08-16-request-5-windows-golden.md`에 기록했습니다.

---

## 7. 확인은 됐지만 golden 파일과 바이트 단위 대조는 안 한 것

- **메타데이터 정책** — `native.task6_metadata_golden`이 macOS `policy-all.tif`를 source로
  네 Windows TIFF를 만들고 root IFD 정책과 보존 문자열 값을 검사합니다. 다만 `tiff-tags.json`과
  모든 값·태그 순서·IPTC IIM/XMP 바이트열을 동일하다고 주장하지는 않습니다.

---

## 다음 한 가지를 고른다면

**순수 ARM64 Windows 장비에서의 실행입니다.** Task 1은 실제 입력의 중앙값 회귀를 닫았지만,
국소 최대 차이는 별도의 macOS 중간-stage golden 없이는 더 줄였다고 주장할 수 없습니다.
