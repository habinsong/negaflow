> # ☠️ 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음 ☠️
>
> **🔬 추측·가설 금지.** "냄새난다" 고 덮지 말고 **냄새의 원인을 찾아 없애십시오.**
> 재현하고, 스택을 잡고, 계측해서 원인을 **확정**한 뒤에 고칩니다.
> 원인을 못 잡았으면 **"못 잡았다" 고 적으십시오** — 추측으로 고친 것은 다음 사람의 함정입니다.
>
> **🌐 모르면 웹 검색을 적극적으로** 하십시오 — 특히 GPU·최적화·UI/UX 구현. 찾은 것은 출처를 남기십시오.
>
> **백엔드**: macOS Swift 파일을 **먼저 열고** 코드를 1:1 로 그대로 옮깁니다.
> 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 마십시오.
> 이름이 같다고 "있음" 으로 적지 마십시오 — **함수 안을 읽고** 판정하십시오.
>
> **프론트엔드**: ① computer-use 로 Windows 앱을 **구역별 크롭**해서 보고
> ② **Parsec 으로 macOS negaflow** 를 같은 구역으로 보고
> ③ **스크린샷 84장**(`negaflow_mac_screenshot/`)을 확인한 **뒤에만** 판정합니다.
> **모양·크기·위치·정렬·색상·내용·텍스트 안 잘림** 일곱 가지를 전부 맞춥니다.
> XAML 에 있다고 "있음" 이 아닙니다 — **화면에 보여야** 있는 것이고,
> **눌러서 값이 안 바뀌면 가짜**입니다.
>
> **저장소**: 본체 `C:\Users\habin\negaflow\`(Apache 2.0) · 스캐너 `C:\Users\habin\negaflow-scanner-sane\`(GPL).
> **두 저장소의 `negaflow-mac\` 은 절대 고치지 마십시오.** 코드 파쿠리·라이선스·특허·저작권 위반 금지.
>
> 규칙 [`00-index.md`](00-index.md) · UI 검증 [`11`](11-ui-verification-protocol.md) · 라이선스 [`12`](12-repos-and-licence.md)

---

---


# 05 — God object (500줄 초과) — 실측

기준: **500줄 초과는 금지. 넘기려면 사유를 이 문서에 적을 것.**
정확히 500줄은 초과가 아니다.

아래는 2026-08-18 22:41에 `negaflow-windows/src`와 `tests`의 `.cs`·`.cpp`·`.h`·`.xaml` **1,229개**(src 982, tests 247)를 물리 줄 수(`ReadLine`)로 다시 잰 것이다. 이 파일의 이전 본문은 같은 날짜로 28+7개를 적었으나, 그 뒤 분해를 반영하지 않았다.

**지금 500줄 초과는 3개다. 사유 없는 초과는 0개다. 미해결 God object 파일은 없다.**

---

## 1. 지금 500줄을 넘는 파일 — 3개

| 줄 | 파일 | 사유 판정 |
|---:|---|---|
| **9,003** | `src/Native/imaging/muted_scene_vibrance_table.cpp` | **사유 있음.** `scripts/generate-civibrance-table.ps1`이 만든 생성 데이터. 첫 줄이 `Do not edit by hand`다. macOS `CIFilter("CIVibrance")`는 Apple 비공개 커널이라 33³×6평면 LUT로 측정해 담았고, golden 해시는 `docs/verification/macos-golden/vibrance/README.md`에 있다. 실행 로직은 `muted_scene_vibrance.cpp`와 `vibrance_math.h`에 있다. 줄만 큰 표이므로 파일 분할은 God object 해소가 아니다 |
| **606** | `tests/Native.UnitTests/DevelopExportAbi/defect_region.cpp` | **사유 있음.** 한 장의 합성 TIFF 위에서 v18–v29 결함 preview/export를 순서대로 묶은 고정 fixture. 뒤 단언이 앞 단계의 화소·SHA·bound 요청을 그대로 쓴다 |
| **526** | `tests/Native.ConformanceTests/scalar_conformance.cpp` | **사유 있음.** scalar/native conformance 단일 suite. 제품 상태·오케스트레이션·I/O를 소유하지 않는다 |

`src/` 생산 코드에서 500줄을 넘는 파일은 생성 표 1개뿐이다.

## 2. 정확히 500줄 — 1개

| 줄 | 파일 | 판정 |
|---:|---|---|
| 500 | `tests/fixtures/tiff/synthetic_wic_tiff.cpp` | 기준선 이하. 테스트 fixture 생성기. 제품 상태·오케스트레이션 없음 |

## 3. 이 문서 이전 본문이 분할 대상으로 적은 파일

이전 본문의 src 28개·tests 7개 중, 1절에 남은 3개를 빼면 **지금은 전부 500줄 이하다.** 이 목록을 보고 다시 쪼개지 마십시오.

| 이전 본문 | 지금 | 파일 |
|---:|---:|---|
| 1,863 | 24 | `src/Native/abi/include/negaflow_abi.h` — 선언 없는 집계 include. 본문은 도메인 헤더 |
| 1,197 | 330 | `src/Native/imaging/infrared_defect_detector.cpp` |
| 945 | 182 | `src/Native/imaging/defect_heal_brush.cpp` |
| 893 | 165 | `src/Native/imaging/auto_negative_base_resolver.cpp` |
| 885 | 286 | `src/Catalog.Core/Storage/CatalogBackupStore.cs` |
| 862 | 116 | `src/Native/imaging/flatbed_frame_grid_detector.cpp` |
| 856 | 100 | `src/Catalog.Core/Defects/DefectSidecarCodec.cs` |
| 849 | 194 | `src/Interop/DevelopExport.cs` |
| 802 | 179 | `src/Native/imaging/film_scan_denoise.cpp` |
| 787 | 22 | `src/Interop/NativeMethods.cs` |
| 765 | 186 | `src/Native/imageio/wic_tiff_decoder.cpp` |
| 713 | 199 | `src/Native/imaging/scanner_target_grade.cpp` |
| 700 | 238 | `src/Catalog.Core/Defects/DefectRecipeValidator.cs` |
| 681 | 220 | `src/Catalog.Core/Storage/CatalogCommitVerifier.cs` |
| 656 | 194 | `src/Native/imaging/local_dodge_burn.cpp` |
| 646 | 211 | `src/Native/imaging/texture_stage.cpp` |
| 597 | 175 | `src/Native/imaging/digital_film_color_preset.cpp` |
| 592 | 256 | `src/Shell.Core/Print/PrintPackageLayout.cs` |
| 577 | 209 | `src/Native/output/wic_jpeg_export.cpp` |
| 570 | 302 | `src/Native/output/wic_tiff_export.cpp` |
| 568 | 188 | `src/Native/imaging/defect_component_structure.cpp` |
| 551 | 266 | `src/Catalog.Core/Defects/DefectSidecarStore.cs` |
| 543 | 389 | `src/Native/imaging/grain_mend_tiled.cpp` |
| 541 | 240 | `src/Catalog.Core/Storage/SqliteCatalogStore.cs` |
| 522 | 184 | `src/Native/imaging/defect_clone_stamp.cpp` |
| 515 | 346 | `src/Native/core/tiff_deflate_validator.cpp` |
| 511 | 117 | `src/Native/abi/detect/grain_mend_detect_abi.cpp` |
| 1,131 | 35 | `tests/Native.UnitTests/grain_mend_tests.cpp` — suite 진입점만 |
| 824 | 23 | `tests/Native.UnitTests/tiff_probe_tests.cpp` |
| 772 | 18 | `tests/Native.UnitTests/manual_negative_developer_tests.cpp` |
| 728 | 36 | `tests/Native.UnitTests/wic_tiff_decoder_tests.cpp` |
| 620 | 22 | `tests/Native.UnitTests/texture_stage_tests.cpp` |

## 4. 500줄 바로 아래 생산 파사드 — 미해결이 아님

줄 수가 커도 이미 협력 타입에 위임하는 공개 파사드다. 새 책임이 붙으면 다시 잰다.

| 줄 | 파일 |
|---:|---|
| 489 | `src/Shell.Core/Develop/DevelopPanelState.cs` |
| 488 | `src/Shell.Core/Library/LibraryHostService.cs` |
| 421 | `src/Shell/Views/DevelopWorkspaceView.xaml.cs` |
| 387 | `src/Shell.Core/Library/LibraryDocument.cs` |

## 5. 더 오래된 문서의 거대 파일 표

`docs/progress/brief-for-agent.md` 11절 · `handoff-2026-08-17-2.md` 10절이 적은 수치는 더 이전이다. 지금 줄 수는 아래다.

| 문서가 적은 것 | 옛 문서의 줄 | 지금 |
|---|---:|---:|
| `src/Native/abi/negaflow_abi.cpp` | 6,264 | **14** |
| `src/Shell/Views/DevelopWorkspaceView.xaml.cs` | 4,835 | **421** |
| `tests/Native.UnitTests/develop_export_abi_tests.cpp` | 4,107 | **파일 없음** (`DevelopExportAbi/`로 이동) |
| `src/Shell/Views/LibraryWorkspaceView.xaml.cs` | 2,835 | **327** |
| `src/Shell/Views/DevelopWorkspaceView.xaml` | 2,508 | **297** |
| `src/Interop/NativeDevelopExporter.cs` | 2,342 | **95** |
| `src/Native/pipeline/develop_export.cpp` | 1,575 | **282** |
| `src/Native/core/tiff_probe.cpp` | 1,425 | **278** |
| `src/Shell/Views/LibraryWorkspaceView.xaml` | 975 | **472** |
| `src/Shell/Views/PrintWorkspaceView.Composition.cs` | 826 | **192** |
| `src/Interop/NativeDevelopExportV2.cs` | (옛 표에 없음) | **파일 없음** (`Interop/DevelopExport/Layout/`로 이동) |

이 표를 보고 일하면 없는 문제를 고칩니다.

`docs/implementation/god-object-remediation.md`, `docs/STATUS.md`, `docs/progress/next-steps.md`의 “947개 중 33개 초과”·`infrared_defect_detector.cpp` 1,197줄 표기도 이 실측과 어긋난다. 줄 수 실측의 자리는 이 파일이다.
