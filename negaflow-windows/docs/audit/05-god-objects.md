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
