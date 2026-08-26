# 2026-08-22 내보내기 속도와 프레임 캐시 배선 검증

기계: Windows 11, 16 코어, NVIDIA GeForce RTX 4060 Ti.
원본: `OneDrive\바탕 화면\negaflow_test\OpticFilm8100_frame_1.tiff` (5088×3401 16bit, 103,825,968 B).
빌드: `x64-release` 네이티브, `x64 Debug` 관리.

측정에 쓴 명령은 전부 `negaflow-cli --export-developed-tiff16 <원본> <대상> 0.30 0.22 0.18 color`
이며, 시간은 그 명령이 내는 JSON 의 `total_wall_microseconds` 와
`stages.output_convert_encode_verify_publish.wall_microseconds` 입니다.

## 1. 설정 "메모리 캐시" 가 엔진 캐시에 닿지 않았다

`ThumbnailService.ApplyResidencySettings` 는 managed BGRA8 표시본 캐시에만 한도를 걸었습니다.
엔진 안의 두 상주 캐시는 설정을 전혀 보지 않았습니다.

| 캐시 | 자리 | 예산을 정하던 근거 |
| --- | --- | --- |
| 디코드 원본 (macOS `cleanedRawImage`) | `export/stages/decode.cpp` `g_decoded_sources` | `decoded_source_budget_bytes()` — 설치 메모리만 |
| 프리뷰 raw 프록시 (macOS `developed` 몫) | `export/support/preview_raw_store.cpp` `g_entries` | `preview_proxy_budget_bytes()` — 설치 메모리만 |

즉 설정에서 자동↔수동을 바꾸거나 수동 프레임 수를 올려도 **엔진 쪽 상한은 그대로**였습니다.

### 고친 자리

- `pipeline/include/negaflow/pipeline/frame_cache_limits.h` (신규) — 프레임 수 두 개를 받는 자리.
- `pipeline/export/support/frame_cache_budget.cpp` — 두 예산 함수가 그 값을 반영. 0/0 이면 자동.
- `abi/include/negaflow/abi/limits.h` · `abi/support/limits_abi.cpp` —
  `nf_set_frame_cache_limits_v1`. `dumpbin /EXPORTS` 로 내보내기 확인함.
- `Interop/NativeLimits.cs` · `Interop/FrameCacheLimits.cs` — P/Invoke 와 `FrameCacheLimitsBridge`.
- `Shell.Core/Library/ThumbnailService.cs` — `ApplyResidencySettings` 가 같은 한도를 엔진에도 건다.
  결과를 `NativeResidencyLimitsApplied` 에 남긴다.

### 검증

`tests/Native.UnitTests/preview_raw_store_tests.cpp` 에 여섯 검사를 더했고 전부 통과했습니다
(`negaflow_preview_raw_store_tests.exe` exit 0, FAIL 0건).

- 한도 4/8 → cleaned raw 예산 `4 × 190MB`, 프리뷰 프록시 예산 `8 × 170MB × 16/20`.
- 한도 2/4 → 두 예산 모두 정확히 절반.
- 0/0 → 두 예산 모두 자동값으로 복귀.

## 2. 내보내기 시간의 76% 가 output 단계였다

수정 전 단계별(한 번 실행):

| 단계 | wall |
| --- | --- |
| decode_and_color_convert | 119.7 ms |
| develop | 354.3 ms |
| tone_adjust | 0.0 ms |
| film_look | 6.1 ms |
| **output (변환·인코딩·검증·게시)** | **1,480.6 ms** |
| 합계 | 1,960.8 ms |

`output` 안에서 쓴 파일을 다시 열어 103MB 를 전부 디코드하고, working 이미지를 sRGB16 으로
**한 번 더** 변환해 바이트 단위로 맞춰 보고 있었습니다
(`wic_srgb16_support.cpp` `verify_working_srgb16_frame` 의 행 고리).

macOS 는 이 대조를 하지 않습니다 — `Chromabase/Export/ExportEngine.swift` 의 `writeTIFF`·
`writePNG` 는 `CGImageDestinationFinalize` 의 성공 여부만 봅니다.

임시로 그 고리만 끄고 A/B 로 잰 값:

| | output | 합계 |
| --- | --- | --- |
| 대조 켬 | 1,592 / 1,728 ms | 2,101 / 2,283 ms |
| 대조 끔 | 856 / 863 ms | 1,337 / 1,355 ms |

### 고친 자리

`WicTiffExportLimits` · `WicPngExportLimits` 에 `verify_pixel_readback` 을 더했고 **기본은 끔**
입니다. 치수·화소형식·해상도·ICC 프로파일 검사와 TIFF 구조·IFD 허용목록 검사는 끄더라도
그대로 돕니다. 인코더가 쓴 화소가 의도한 화소와 같다는 증명은 단위 시험 아홉 자리가 이 값을
켜서 들고 있습니다(`wic_tiff_export_tests` 4곳, `wic_png_export_tests` 5곳).

CLI JSON 의 `pixels_verified` 는 이제 실제 값을 냅니다 — 예전에는 문자열에 `true` 가 박혀
있었습니다.

### 검증

| | 합계 |
| --- | --- |
| 이전 | 2,101 / 2,283 ms |
| 이후 | 1,315 / 1,261 / 1,255 ms |

**약 42% 단축.** 내보낸 파일의 SHA-256 은 이전·이후 모두 `851986B5D6C61B7009927148…` 로
같습니다 — 화소는 하나도 달라지지 않았습니다. 네이티브 CTest 102/102 통과.

## 3. 배치 내보내기가 한 장씩만 돌았다

`ExportBatchCoordinator.RunAsync` 는 `foreach` 로 한 장씩 await 했고,
`DevelopExportCoordinator` 의 단일 실행 잠금이 0↔1 이라 두 번째 장은 곧바로 `Busy` 였습니다.

기존 주석은 "현상 한 장이 이미 모든 코어를 쓰므로 동시에 돌려도 전체 시간은 그대로" 라고
적혀 있었는데 실측이 다릅니다 — 한 장 내보내기의 `total_cpu_microseconds` 는 5,109,375,
`total_wall_microseconds` 는 1,960,812 로 **16 코어에서 병렬도 2.6** 입니다. 103MB 를 디스크에
쓰는 구간에서는 CPU 가 통째로 놉니다.

macOS 는 `AppModel+BatchExport.swift:130` 에서 `runExportBatch(plans, maximumConcurrent: 2)`
로 돌리고, `ExportBatchScheduler` 가 워커에게 **공유 커서**로 다음 장을 하나씩 나눠 줍니다
(워커마다 인덱스를 미리 나누면 느린 한 장이 자기 뒤를 전부 막습니다).

### 고친 자리

- `Shell.Core/Develop/ExportBatchScheduler.cs` (신규) — macOS `ExportBatchScheduler` 이식본.
- `Shell.Core/Develop/DevelopExportCoordinator.cs` — 잠금을 세는 값으로 바꾸고
  `MaximumConcurrentExports = 2`. **기본 한도는 1** 이라 단일 내보내기 거동은 그대로입니다.
- `Shell.Core/Library/LibraryHostService.cs` · `Shell.Core/Develop/ExportBatch.cs` — 배치만 2 를 넘김.

### 검증

frame_1 · 10 · 11 · 13 네 장(모두 5088×3401):

| | 시간 |
| --- | --- |
| 순차 (readback 제거 뒤) | 6,135 ms |
| 동시 2장 | 3,741 ms |

**1.64×.** 네 장의 SHA-256 은 순차본과 전부 같습니다.

readback 제거까지 합치면 네 장 배치가 약 8,768 ms → 3,741 ms 로 **2.34×** 입니다.

## 4. 내보내기 TIFF 압축에서 LZW 를 뺐다

`ExportSettings.TiffCompressionOptions` 는 이제 없음·Deflate 둘뿐이고, 저장돼 있던 LZW 는
`Normalize()` 와 `Sanitized()` 가 Deflate 로 옮깁니다. 열거자와 ABI 는 그대로 둡니다 —
스캐너가 내놓는 LZW TIFF 를 **읽는** 경로와 이미 나간 사이드카가 그 값을 씁니다.

LZW 는 사전 기반 바이트 부호라 16bit 표본에서 되풀이가 거의 잡히지 않습니다. macOS
`ImageLoader.swift:34` 도 같은 원본을 두고 "LZW 압축본 9.5초 / 비압축본 1.1초" 라고 적어
두었습니다.

## 5. 아직 검증하지 않은 것

- 컬러 믹서 슬라이더(`ColorMixerEditor`)와 인화 세로사진 눌림(`PrintPreviewRenderer`) 수정은
  **빌드와 단위 시험까지만** 확인했습니다. 실제 창에서 끌어 보고 세로 사진을 얹어 본 증거는
  아직 없습니다.
- 관리 단위 시험은 이 시점에 10건 실패인데 전부 `ScannerWorkflowTests`·`ScanSessionTests`
  (flatbed / scan session)이며, 다른 세션이 `FlatbedScanRegion` 을 좌표계째 바꾸는 중이라
  생긴 것입니다. 내보내기 관련 검사는 전부 통과합니다.
