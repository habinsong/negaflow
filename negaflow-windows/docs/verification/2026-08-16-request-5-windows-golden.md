# REQUEST-5 golden — Windows에서 재현한 범위

기준일: 2026-08-16

## 실행한 항목

macOS에서 확정해 저장소에 올린 `docs/verification/macos-golden/REQUEST-5.md`와 golden
자산을 Windows x64 Debug에서 직접 사용했다. macOS 앱을 Windows에서 빌드하거나 실행하지는
않았다.

| 요청 항목 | Windows 결과 | 근거 |
| --- | --- | --- |
| 1. scanner target·profile | 실제 source 중앙값 회귀 | 저장소 밖에서 제공된 GT-X900 TIFF의 SHA-256이 macOS manifest와 일치함을 먼저 확인하고, 여덟 Windows ABI v32 export를 macOS TIFF golden과 비교했다. 모든 RGB16 channel median은 절대값 96 코드(8-bit 0.4 레벨) 이내다. |
| 6. metadata policy | 실제 source 정책 회귀 | macOS `policy-all.tif`를 source로 네 Windows TIFF를 다시 만들고 root IFD의 Artist/Copyright/ImageDescription 문자열 값 및 EXIF·IPTC·GPS 보존/제거를 `native.task6_metadata_golden`에서 확인했다. IPTC IIM/XMP 바이트열과 파일별 태그 순서의 동일성은 주장하지 않는다. |
| 7. Core Image filters | 경계 포함 회귀 상한 | CIUnsharpMask 6개, clarity 양수 3·음수 2(반경 7·10) stage 출력과 CIGaussianBlur 1.0·1.3·2.4·4.0·7.0·10.0 direct RGBAf fixture를 `native.texture_stage`에서 비교했다. 최악 절대 차이는 0.008 미만이다. 공통 `sigma² = radius² + 0.08` 사상은 실제 heal-brush 1.0·FilmScanDenoise 1.3에도 사용한다. 2.4는 현재 macOS 제품 호출 경로가 없는 ScannerNoiseReduction 정의뿐이어서 Windows 기능을 임의로 추가하지 않았다. |
| 8. Digital Film Look | 회귀 상한 | Portra 400, Velvia 50, Tri-X 400 각 0.5/1.0의 RGBAf 6장을 `native.working_film_look`에 연결했다. 관측 최댓값은 0.004713 미만이며 검증 상한은 0.005이다. |
| 9. 실입력 B&W/슬라이드 | 중앙값 회귀 범위 통과 | 15개 1768×2906 RGB16 TIFF를 실제 ABI v32 export로 다시 만들고 WIC로 golden과 비교했다. color-positive는 32, B&W는 64 RGB16 코드의 채널 중앙값 한계를 자동 검증한다. |
| CIVibrance | 전 slider 범위 회귀 | 33³ 표의 음수/양수 plane을 사용해 macOS f32 17장을 `native.color_model`에서 확인했다. |

## Task 1 수치 — 실제 V700 source

Task 1 source `GT-X900_frame_4.tiff`는 저장소에 복사하지 않았으며 manifest의 47,316,912 bytes 및
SHA-256 `9e3d0daf2537273a299d5a77ed17c2d3c617131e59cc6afa9d90daf867d1a198`를 확인했다. 새
`negaflow_task1_pixel_golden_tests`는 source와 각 macOS output의 manifest SHA-256을 검사하고,
실제 ABI v32 TIFF16 export의 WIC RGB16 channel median이 96 코드를 넘으면 실패한다.

| 조건 | median R/G/B | max abs R/G/B |
| --- | --- | --- |
| a-default-main-srgb | +13 / +49 / +56 | 2328 / 2249 / 1767 |
| b-main-scannerprofile-portra400-srgb | −18 / +9 / +6 | 5677 / 6482 / 5705 |
| c-target-hs-srgb | +23 / +48 / +63 | 4478 / 3102 / 3061 |
| c-target-sp-srgb | +15 / +85 / +55 | 2954 / 2601 / 3921 |
| c-target-f135-srgb | +16 / +43 / +49 | 2612 / 2381 / 2671 |
| c-target-hr-srgb | 0 / +53 / +54 | 2730 / 2587 / 2743 |
| d-main-displayp3 | +20 / +49 / +55 | 2216 / 2242 / 1320 |
| d-main-adobergb | +19 / +45 / +51 | 1848 / 1919 / 1335 |

Portra 400의 종전 중앙값 차이는 Windows의 `ScannerProfileGrade`가 `CIToneCurve` control point를
선형광에 적용한 결함이었다. macOS의 감마 2 지각 작업 공간 spline 의미로 바꾼 뒤 중앙값이
`−876/−616/−550`에서 `−18/+9/+6`으로 수렴했다. max abs는 여전히 크므로 pixel-exact 동등성이나
CI 내부 neighborhood filter의 동일성을 주장하지 않는다.

## Task 9 수치

색상 양화 8개는 RGB16 채널 중앙값 차이가 -7부터 +19 코드였고, 테스트는 절대값 32 코드
이하를 요구한다. 기본 sRGB는 최대 절대 차이도 채널당 1 코드였다. scanner-profile/타겟
경로에는 국소 최대 차이(최대 1,561 코드)가 남아 있으므로 중앙값 통과를 pixel-exact 동등성으로
해석하지 않는다.

B&W 음화 7개는 Windows 자동 base가 중립 fallback을 측정값처럼 취급해 크로모제닉 재시도를
건너뛰던 제어 흐름을 고쳤습니다. 기본 case에서 Windows Dmin은
`(0.143874, 0.296173, 0.432927)`로, macOS manifest의 `(0.144379, 0.296712, 0.433473)`에
수렴합니다. 7개 중앙값 차이는 0부터 −56 RGB16 코드이며 B&W 회귀 한계는 64 코드입니다.
Noritsu case의 국소 최대 차이 1,093 코드는 남으므로 이 통과를 pixel-exact 동등성으로
해석하지 않습니다.

## 실행 명령

```powershell
cmake --preset x64-debug
cmake --build --preset x64-debug --target negaflow_task1_pixel_golden_tests negaflow_task6_metadata_golden_tests negaflow_texture_stage_tests negaflow_film_scan_denoise_tests negaflow_defect_heal_brush_tests negaflow_color_model_tests negaflow_scanner_profile_grade_tests negaflow_working_film_look_tests negaflow_task9_bw_slide_golden_tests negaflow_wic_tiff_export_tests negaflow_manual_negative_developer_tests
./out/build/native/x64-debug/Debug/negaflow_task1_pixel_golden_tests.exe <GT-X900_frame_4.tiff> ./docs/verification/macos-golden/task1-pixels
ctest --preset x64-debug -R '^(native\.task6_metadata_golden|native\.texture_stage|native\.color_model|native\.scanner_profile_grade|native\.working_film_look|native\.wic_tiff_export|native\.manual_negative_developer)$' --output-on-failure
ctest --preset x64-debug -R '^(native\.texture_stage|native\.film_scan_denoise|native\.defect_heal_brush)$' --output-on-failure
ctest --preset x64-debug -R '^native\.task9_bw_slide_golden$' --output-on-failure
ctest --preset x64-debug -R '^(native\.working_to_srgb16|native\.wic_png_export|native\.wic_tiff_export|native\.scanner_to_working|native\.scanner_target_grade|native\.develop_export_abi)$' --output-on-failure
./scripts/test-managed.ps1 -Preset x64-debug
./scripts/ci-gate.ps1 -Preset x64-release
./scripts/ci-gate.ps1 -Preset x64-release -IncludeArm64Cross
```

새 Task6/Texture/auto-base CTest는 3/3 통과했다. 이후 공통 Gaussian 사상을 실제
heal-brush·FilmScanDenoise와 함께 다시 빌드하고 `native.texture_stage`,
`native.film_scan_denoise`, `native.defect_heal_brush` 3/3을 통과했다. Task 9는 1/1,
기존 출력 경로 CTest는 6/6 통과했다. Debug Task 9 전체 재검증은 대형 TIFF 15개를 다시 써서
121.46초가 걸렸다.
최종 x64 Release gate는 native 71/71, Catalog 721 assertion, Shell 905 assertion을 모두
통과했다. 그 뒤 root 문자열 값 비교를 더한 `native.task6_metadata_golden`도 x64 Release에서
1/1 통과했다. 공통 Gaussian 사상 변경 뒤에도 x64 Release `ci-gate`의 native CTest 71/71과
`test-managed.ps1 -Preset x64-release`의 Catalog 721/Shell 905 assertion이 다시 통과했다.
`-IncludeArm64Cross`는 순수 ARM64 native와 managed graph를 교차 빌드했고 native DLL의 PE machine은
`0xAA64`이며, 별도 ARM64 managed build도 경고·오류 없이 통과했다. 이는 ARM64 runtime 결과가 아니다.

## 남은 경계

- Task 1은 중앙값 회귀만 닫았다. Portra 400의 국소 최대 절대 차이 6,482 RGB16 코드와 HS/SP의
  국소 차이는 남아 있으며, 이 기록은 pixel-exact 동등성 주장이 아니다.
- B&W Task 9의 중앙값 base 회귀는 닫혔지만, Noritsu의 국소 최대 차이 1,093 RGB16 코드는 남아 있다.
- 순수 ARM64 Windows 장비에서의 실행은 이 기록의 범위가 아니다.
