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

기준: **500줄 초과는 금지. 넘기려면 사유를 문서에 적을 것.**
아래는 2026-08-18 에 `wc -l` 로 직접 잰 것입니다.

---

## 1. `src/` — 28개

| 줄 | 파일 | 사유 판정 |
|---:|---|---|
| **9,003** | `src/Native/imaging/muted_scene_vibrance_table.cpp` | **사유 있음(정당).** `scripts/generate-civibrance-table.ps1` 이 만든 **생성 파일**. macOS `CIFilter("CIVibrance")` 는 Apple 비공개 커널이라 33³×6평면 LUT 로 측정 이식했고 golden 해시가 `docs/verification/macos-golden/vibrance/README.md` 에 있음. 손으로 고칠 파일이 아님 |
| **1,863** | `src/Native/abi/include/negaflow_abi.h` | **사유 필요.** ABI 표면 전체. 버전별로 쪼갤 수 있음 |
| **1,197** | `src/Native/imaging/infrared_defect_detector.cpp` | **분할 필요.** macOS 는 같은 일을 11파일 1,584줄로 나눔(`InfraredDefectRemoval+Alignment/Baseline/Clusters/Components/Confirmation/Planes/Spectral/…`) |
| 945 | `src/Native/imaging/defect_heal_brush.cpp` | 분할 필요 |
| 893 | `src/Native/imaging/auto_negative_base_resolver.cpp` | 분할 필요. macOS 는 `FilmBaseEstimator`+`Statistics`+`SampleGrid`+`MeasurementDiagnostics` 4파일 |
| 885 | `src/Catalog.Core/Storage/CatalogBackupStore.cs` | 분할 필요 |
| 862 | `src/Native/imaging/flatbed_frame_grid_detector.cpp` | 분할 필요. macOS 는 4파일 |
| 856 | `src/Catalog.Core/Defects/DefectSidecarCodec.cs` | 분할 필요 |
| 849 | `src/Interop/DevelopExport.cs` | 분할 필요 |
| 802 | `src/Native/imaging/film_scan_denoise.cpp` | 분할 필요 |
| 787 | `src/Interop/NativeMethods.cs` | P/Invoke 표면 — 사유 필요 |
| 765 | `src/Native/imageio/wic_tiff_decoder.cpp` | 분할 필요 |
| 713 | `src/Native/imaging/scanner_target_grade.cpp` | 분할 필요. macOS 는 8파일 1,697줄 |
| 700 | `src/Catalog.Core/Defects/DefectRecipeValidator.cs` | 분할 필요 |
| 681 | `src/Catalog.Core/Storage/CatalogCommitVerifier.cs` | 분할 필요 |
| 656 | `src/Native/imaging/local_dodge_burn.cpp` | 분할 필요 |
| 646 | `src/Native/imaging/texture_stage.cpp` | 분할 필요 |
| 597 | `src/Native/imaging/digital_film_color_preset.cpp` | 분할 필요 |
| 592 | `src/Shell.Core/Print/PrintPackageLayout.cs` | 분할 필요 |
| 577 | `src/Native/output/wic_jpeg_export.cpp` | 분할 필요 |
| 570 | `src/Native/output/wic_tiff_export.cpp` | 분할 필요 |
| 568 | `src/Native/imaging/defect_component_structure.cpp` | 분할 필요 |
| 551 | `src/Catalog.Core/Defects/DefectSidecarStore.cs` | 분할 필요 |
| 543 | `src/Native/imaging/grain_mend_tiled.cpp` | 분할 필요 |
| 541 | `src/Catalog.Core/Storage/SqliteCatalogStore.cs` | 분할 필요 |
| 522 | `src/Native/imaging/defect_clone_stamp.cpp` | 분할 필요 |
| 515 | `src/Native/core/tiff_deflate_validator.cpp` | 분할 필요 |
| 511 | `src/Native/abi/detect/grain_mend_detect_abi.cpp` | 분할 필요 |

## 2. `tests/` — 7개

| 줄 | 파일 |
|---:|---|
| 1,131 | `tests/Native.UnitTests/grain_mend_tests.cpp` |
| 824 | `tests/Native.UnitTests/tiff_probe_tests.cpp` |
| 772 | `tests/Native.UnitTests/manual_negative_developer_tests.cpp` |
| 728 | `tests/Native.UnitTests/wic_tiff_decoder_tests.cpp` |
| 620 | `tests/Native.UnitTests/texture_stage_tests.cpp` |
| 606 | `tests/Native.UnitTests/DevelopExportAbi/defect_region.cpp` |
| 526 | `tests/Native.ConformanceTests/scalar_conformance.cpp` |

---

## 3. 기존 문서의 God object 표는 **전부 낡았습니다**

`docs/progress/brief-for-agent.md` 11절 · `handoff-2026-08-17-2.md` 10절 의 표를 실측했습니다.

| 문서가 적은 것 | 문서의 줄 | **실제** |
|---|---:|---:|
| `src/Native/abi/negaflow_abi.cpp` | 6,264 | **14** |
| `src/Shell/Views/DevelopWorkspaceView.xaml.cs` | 4,835 | **329** |
| `tests/Native.UnitTests/develop_export_abi_tests.cpp` | 4,107 | **파일 없음** |
| `src/Shell/Views/LibraryWorkspaceView.xaml.cs` | 2,835 | **327** |
| `src/Shell/Views/DevelopWorkspaceView.xaml` | 2,508 | **297** |
| `src/Interop/NativeDevelopExporter.cs` | 2,342 | **95** |
| `src/Native/pipeline/develop_export.cpp` | 1,575 | **256** |
| `src/Native/core/tiff_probe.cpp` | 1,425 | **278** |
| `src/Shell/Views/LibraryWorkspaceView.xaml` | 975 | **472** |
| `src/Shell/Views/PrintWorkspaceView.Composition.cs` | 826 | **192** |

**10개 전부 이미 쪼개졌는데 문서는 그대로였습니다.** 이 표를 보고 일하면 없는 문제를 고칩니다.
