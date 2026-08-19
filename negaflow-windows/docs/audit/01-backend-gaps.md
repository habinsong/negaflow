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
> ③ **스크린샷 50장**(`C:\Users\habin\맥negaflow 스크린샷\`)을 확인한 **뒤에만** 판정합니다. 폴더·파일 전체 목록은 [`11`](11-ui-verification-protocol.md) 1.3절.
> **모양·크기·위치·정렬·색상·내용·텍스트 안 잘림** 일곱 가지를 전부 맞춥니다.
> XAML 에 있다고 "있음" 이 아닙니다 — **화면에 보여야** 있는 것이고,
> **눌러서 값이 안 바뀌면 가짜**입니다.
>
> **화면 도구 — 자세히.** `windows-mcp` / `windows-gui` MCP 는 **절대 금지.** 켜지 말고 호출하지 말고 대용으로도 쓰지 마십시오. Windows 앱·Parsec 맥 화면은 **computer-use 만.** computer-use 도 **꼭 필요할 때만** 씁니다(토큰). **씁니다:** 이 작업에서 화면에 보이는지·눌러서 값이 바뀌는지·잘림/정렬/색을 새로 판정해야 하고 코드·단위시험·스크린샷 50장·기존 로그로는 부족할 때. **쓰지 않습니다:** 백엔드·네이티브·시험만 고칠 때, 스크린샷 폴더+Swift/XAML 으로 충분할 때, 방금 본 화면을 다시 찍을 때, "일단 띄워 보자" 탐색. 쓸 때도 전체를 반복 찍지 말고 **해당 구역만 크롭.** 전문은 [`00`](00-index.md) · [`11`](11-ui-verification-protocol.md).
>
> **저장소**: 본체 `C:\Users\habin\negaflow\`(Apache 2.0) · 스캐너 `C:\Users\habin\negaflow-scanner-sane\`(GPL).
> **두 저장소의 `negaflow-mac\` 은 절대 고치지 마십시오.** 코드 파쿠리·라이선스·특허·저작권 위반 금지.
>
> 규칙 [`00-index.md`](00-index.md) · UI 검증 [`11`](11-ui-verification-protocol.md) · 라이선스 [`12`](12-repos-and-licence.md)

---

---


# 01 — 백엔드 감사 (엔진)

macOS `Sources/Chromabase/` **159파일**을 개념 키워드로 Windows 전 트리에 대조했습니다.
히트 0 = 한 글자도 없음. 히트가 있으면 파일을 열어 함수·상수 단위로 확인했습니다.

---

## 1. 완전히 없음 — 2026-08-19 재집계

2026-08-18 표의 "28개 개념 히트 0" 은 **그 날 아침** 기준입니다. GPU·필름 베이스 진단·8bit 디더·
클리핑 오버레이·현상 undo 는 그 뒤에 붙었습니다. 아래는 **지금 없는 것**만 남깁니다.

### 1.1 GPU · 실행 장치 — **있음. 이 절은 닫음**

`src/Native/gpu/` cpp/h **60** + 셰이더 **38**. `ID3D11Device` 히트 있음.
3.1–3.8 닫힘. 다시 이식하지 말 것. [`15`](15-gpu-handoff.md).

`SamplingContextPool` 이름은 없습니다. Core Image 는 Windows 에 없습니다 — D3D11 컴퓨트가
그 자리입니다.

### 1.2 현상 경로

| macOS | Windows | 영향 |
|---|---|---|
| `Engine/ChromabaseEngine+PositivePipeline.swift` | **없음** | 슬라이드(포지티브) 현상 경로 전체 |
| `Film/PositiveDevelop.swift` | **없음** | 〃 |
| `Adjustments/FilmEmulationProfile+Slide.swift` | **없음** | 슬라이드 필름 에뮬레이션 |
| `Digital/DigitalFilmDevelop.swift` | **없음** | 디지털 소스 현상 |
| `Digital/DigitalSceneReconstruct.swift` | **없음** | 디지털 장면 재구성 |

### 1.3 편집 상태 · 이력

| macOS | Windows | 지금 |
|---|---|---|
| `DevelopHistory` / `AppModel+FrameEditHistory` | `FrameEditHistory` + `DevelopInspectorResetter` | **2026-08-19 붙음.** 초기화 undo · 슬라이더 0.7s 묶음. 히스토리 **패널**은 없음 |
| `AppModel+DefectHistory` | `DevelopPanelState.CanUndoDefectEdit` | 결함 undo 게이트는 있음. 205줄 이력 **패널**은 없음 |
| `DevelopKeyboardNudge` | **없음** | 키보드 미세 조정 |
| `DevelopToneRange` | **없음** | 톤 범위 모델 |
| `DevelopDebugFrame` | **없음** | 개발자 모드 디버그 오버레이 |

### 1.4 스캐너 프로파일링

| macOS | 파일 | 줄 | Windows |
|---|---:|---:|---|
| `Profiles/Noise/*` | 4 | 364 | **없음** (`ScannerNoiseReduction` 도 3파일 전부 없음) |
| `Adjustments/ScannerNoiseReduction*.swift` | 3 | — | **없음** |
| `Profiles/ColorTarget/*` (IT8) | 6 | **3,255** | **없음** |
| `Profiles/ScannerProfile/ScannerProfileRegistry.swift` | 1 | — | **없음** |

**IT8 프로파일링 3,255줄이 통째로 없습니다.**

### 1.5 내보내기 · 기록

| macOS | 파일 | Windows |
|---|---:|---|
| `Export/RenderManifest*.swift` | 5 | **없음** — 무엇을 어떤 설정으로 냈는지 기록·해시·검증 |
| `Export/DestinationGamutWarning.swift` | 1 | **없음** |
| `Export/ICCOutputProfileSnapshot.swift` | 1 | **없음** |
| `Export/ExportEngine.swift` | 1 | **없음** |
| `Export/ExportRenderedImage.swift` | 1 | **없음** |
| `Export/PrintPackageRenderer.swift` | 1 | **없음** |
| `Imaging/ChannelClippingOverlay.swift` | 1 | **2026-08-19 붙음.** 설정 토글 + 프리뷰 합성 + GPU 비트 일치. 앱 토글 실측은 못 함([`15`](15-gpu-handoff.md) 3.3) |
| `Adjustments/OutputDither.swift` | 1 | **있음.** 8bit CPU 경로 `quantize_component_8` · 프리뷰 `display_dither_offset`. 별도 GPU 패스 없음 |

### 1.6 필름 베이스 측정

| macOS | Windows |
|---|---|
| `Film/FilmBaseMeasurementDiagnostics.swift` (186) | **2026-08-19 이식함** → `film_base_measurement.h/.cpp` + 내보내기 sidecar `filmBaseDiagnostics`. 앱 JSON `confidence=0.7291067` · `measuredEvidenceScoreV1` |
| `Film/FilmBasePicker.swift` (149) | **2026-08-18 이식함** → `imaging/film_base_picker.cpp`(268) + `abi/pick/film_base_pick_abi.cpp` + `Interop/FilmBasePick.cs`. 시험 `native.film_base_picker` 7개 |
| `Film/FilmBaseSampleGrid.swift` (64) | **이름만 없고 이식돼 있음** — `film_base_sampling.cpp` 의 `SampleGrid`·`make_sample_grid`·`make_sample_grid_geometry` |
| `Film/FilmBaseStatistics.swift` (44) | **이름만 없고 이식돼 있음** — `coherentCluster`/`median`/`percentile` 셋 전부 `film_base_sampling.cpp` 의 `coherent_measurement`/`median`/`percentile`. **앞 판정이 틀렸습니다** — 파일명으로 찾아 "없음" 으로 적었던 것 |
| `Film/PrintPaperGrade.swift` | **없음**(엔진 쪽) |

### 1.7 GrainMend 내부

| macOS | Windows |
|---|---|
| `DefectRemoval/DefectContext.swift` | **없음** |
| `DefectRemoval/DefectLabeledMask.swift` | **없음** |
| `DefectRemoval/DefectParallelAccumulators.swift` | **없음** |
| `DefectRemoval/ConcurrentResultStore.swift` | **없음** |
| `DefectRemoval/DefectBench*.swift` (4) | **없음** (벤치 도구) |

---

## 2. 있으나 macOS 의 절반 이하 — "얇은 구현"

줄 수는 규모의 지표일 뿐이지만, **절반 이하는 기능이 빠졌다는 뜻**입니다.

| 서브시스템 | macOS | Windows | 비 | 무엇이 빠졌나 |
|---|---:|---:|---:|---|
| `Profiles/ScannerTargetGrade` (8파일) | 1,697 | 749 | **44%** | `+Signature`·`+PositiveSignature`·`+Texture`·`+DocumentedCharacter` 히트 **0** |
| `Profiles/ScannerProfile` (5파일) | 681 | 297 | **44%** | `ScannerProfileRegistry` 없음, `Matcher` 히트 1 |
| `Engine` (6파일) | 1,718 | 256 | **15%** | 포지티브 파이프라인·Metal 커널·샘플링 풀 없음 |
| `Film` (11파일) | 1,993 | 1,379+ | **진단+sidecar+baseRGB+피커276+리베이트 집기** | C1.5~C1.9 |
| `Digital` (13파일) | 2,435 | 1,618 | **66%** | `DigitalFilmDevelop`·`SceneReconstruct` 없음 |
| `Export` (23파일) | 3,985 | 2,703 | **68%** | `RenderManifest` 5파일·감마워닝·ICC 스냅샷 없음 |

---

## 3. 구조 문제 — 성능의 근본 원인

### 3.1 `run_develop` 이 호출마다 원본을 디코드합니다

`src/Native/pipeline/develop_export.cpp:101`

```
run_develop()
  → validate_request
  → observe_source_before   ← 파일 관찰·해시
  → decode_source           ← 5088×3401 16bit TIFF 디코드 (실측 2,695 ms)
  → apply_defect_stage → ... → publish_developed
```

`decode.cpp` 는 **프레임 키 FIFO + mutex + `shared_ptr`** 입니다(2026-08-19).
프로세스 전역 단일 슬롯은 지웠습니다 — 썸네일이 현상 슬롯을 덮어 UAF 가 났습니다([`07`](07-user-reported.md) H).

프리뷰 raw 는 `preview_raw_store` 가 프레임별로 인터랙티브/정착 두 슬롯을 들고,
정착 raw 가 있으면 인터랙티브를 Lanczos 로 파생합니다(디코드 0).
관리 쪽 `FrameResidency` 가 developed FIFO 입니다. 설정 탭의 메모리 캐시 UI 는 없습니다([`10`](10-cache-and-optimization.md)).

프리뷰·검출·내보내기는 같은 `run_develop` 입니다. 프리뷰만 상자 크기에서 현상합니다.
검출과 내보내기는 원본 해상도입니다.

**macOS 는 정반대입니다** (`DevelopFrameRenderer+Input.swift:48-66`):

```swift
if let cached = snapshot.preloadedPreviewRaw { return ... }   // 디코드 0회
if let full = snapshot.preloadedFullPreviewRaw { ... }        // GPU Lanczos 축소만
```

주석 원문: *"수십 MP 원본을 디스크에서 재디코딩(수백 ms)하는 대신 한 번의 Lanczos 축소로 끝난다."*

### 3.2 macOS 의 2단 렌더 — 2026-08-18 이식됨(효과 미측정)

| macOS | 값 | Windows |
|---|---|---|
| `interactiveMaxDimension` | 2560 (폴백) | `DevelopPreviewProxy.cs` |
| `interactiveProxyDimension()` | 표시 픽셀 → 256 양자화, 1024~3600 | 〃 |
| `fullMaxDimension` (정착) | 3600 | 〃 |
| `fastPreviewMaxDimension` | 720 | 〃 |
| `waitForDevelopSettle` | **0.14초** 무편집 대기 | 〃 |
| `cachedInteractivePreviewRaw` / `cachedSettledPreviewRaw` | 두 슬롯 | `preview_raw_store` **프레임별** 2슬롯 |

`DevelopPreviewProxy.cs` 가 macOS 상수(1024…3600, step 256, settle 0.14s)를 갖고,
`PreviewCoordinator` 가 표시 크기 적응 패스 뒤 무편집 0.14초면 3600 정착을 돌립니다.
고정 1600×1200 은 없습니다. 인터랙티브 상자 접기는 넣었다가 되돌렸습니다([`07`](07-user-reported.md) H.9).

CLI: 5088×3401 상자 1280 두 번째 **43.1 ms · decode 0**. 3600 `nocurve` 단계 합 **65.0 ms**.
앱 슬라이더 벽시계는 **못 쟀습니다.**

---

## 4. 창작 — macOS 에 없는 것

| Windows | 줄 | 판정 |
|---|---:|---|
| `imaging/muted_scene_vibrance_table.cpp` | 9,003 | **정당함.** macOS 는 `CIFilter("CIVibrance")` 라는 Apple 비공개 커널을 씁니다. Windows 는 그것을 33³ LUT 로 **측정해** 옮겼고 golden 해시가 문서에 있습니다. 창작이 아니라 이식 수단입니다. [`05`](05-god-objects.md) 에 사유 있음. **다시 쪼개지 말 것** |
| `DefectOverlayImage` 의 `Opacity="0.75"` | 1줄 | **창작이었음 — 2026-08-18 제거.** macOS 는 불투명도를 색마다 넣습니다 |
| `NativeEngineStatusService` 의 `ABI 0.48 · X64` | — | **창작이었음 — `f5d9a5b` 에서 제거** |
| GrainMend 캡슐 `CornerRadius="999"` | — | **창작이었음 — `f5d9a5b` 에서 18/15 로 수정** |

---

## 5. 대조 결과 "맞음" (오해 방지)

| 항목 | 결과 |
|---|---|
| 점 커브 보간 | macOS `CurveLUT.monotoneTangents` (Fritsch–Carlson PCHIP)가 `point_curve.cpp:158-186` 에 **정확히** 있음 — `deltas`, `0.5` 평균, `> 9.0` 클램프, `3/sqrt` 까지 동일 |
| `gridLineDrops` ↔ `structure_grid_drops` | 두 메커니즘·보조 함수·상수 12개 전부 일치 |
| 먼지·핀홀·유제 검출 | 다섯 프레임 전부 macOS 와 개수 정확히 일치 |

**`MonotoneCubic` 이름이 없다고 "톤 곡선이 macOS 와 다르다"고 적은 기존 문서는 틀렸습니다** —
[`06-false-claims.md`](06-false-claims.md) 1절.

---

## 6. GPU 이식이 드러낸 결손 (2026-08-18)

커널을 옮기면서 macOS `[[stitchable]]` 커널 32개의 Windows 대응을 **하나씩 열어 확인**했습니다.
그 과정에서 나온 결손입니다 — 이름이 아니라 **개념어로** 훑어 확정한 것들입니다.

| macOS 커널 | Windows | 확인 방법 |
|---|---|---|
| `digitalSceneReconstruct` | **없음** | `scene_reconstruct` 로 `src/Native/` 전수 → 히트 0 |
| `digitalFilmDensity` | **없음** | `film_density` → 히트 0 |
| `digitalInterImage` | **없음** | `inter_image` → 히트 0 |
| `digitalPrintPaper` | **없음** | `print_paper` → 히트 0 |
| `digitalReversalTransmit` | **없음** | `reversal_transmit` → 히트 0 |
| `digitalToDisplayGamma` | **없음** | `digital_halation.cpp` 안에도 없음 |
| `digitalToLinearLight` | **없음** | 〃 |
| `ditherAdd` | **없음** | `OutputDither.swift` 미이식 — 1.3절과 같음 |
| `channelClippingOverlay` | **없음** | `ChannelClippingOverlay.swift` 미이식 |

**`digital_film_physics.cpp` 는 이것들의 구현이 아닙니다.** 프로파일 표입니다.

`digitalToDisplayGamma`·`digitalToLinearLight` 는 이식했습니다.
`ditherAdd`·`channelClippingOverlay` 는 1.5절 — **있음.**

`digitalSceneReconstruct`·`digitalFilmDensity`·`digitalInterImage`·`digitalPrintPaper`·
`digitalReversalTransmit`·`digitalFilmColor` 여섯은 **macOS 에서도 죽은 커널**입니다
([`06`](06-false-claims.md) 11절). **옮기지 마십시오.**

살아 있는 디지털 룩은 `DigitalFilmColorPresetStage` / `digital_film_color_preset.cpp` 입니다.


---

## 9. 2026-08-20 — 엔진에서 고친 것

### 9.1 `develop_export.cpp` 소멸 순서 (강제 종료의 원인)

`GpuResidentScope` 를 **단계 출력보다 뒤에** 선언해 두었습니다. C++ 는 선언의 역순으로
지우므로 상주 범위가 먼저 죽고, 그 소멸자의 `flush_resident()` 가 **이미 사라진**
`InvertStageOutput`/`LookStageOutput`/`GrainStageOutput`/`FinishStageOutput` 에
화소를 내려썼습니다. 앱에서는 자동 레벨 단추를 3번쯤 누르면 `0xC0000005` 로 죽었습니다.

```cpp
// 고친 뒤 — 출력이 먼저, 상주 범위가 나중(= 상주 범위가 먼저 죽고 출력은 살아 있음)
InvertStageOutput invert{};
LookStageOutput look{};
GrainStageOutput grain{};
FinishStageOutput finish{};

std::optional<GpuResidentScope> resident_scope{};
if (gpu_policy == GpuUsePolicy::allowed) { resident_scope.emplace(); }
```

**규칙 ①: 상주 범위는 그것이 채우는 버퍼보다 먼저 선언합니다.**

### 9.1.1 그것만으로는 부족했습니다 — `flush_resident_if`

같은 날 타깃을 잇달아 바꾸니 또 죽었습니다. 선언 순서는 **함수 지역 변수**만 고칩니다.
단계 함수들은 이미지를 **값으로 받아 다 쓰고 버리므로**, 그 중간 버퍼가 묶인 채
사라지면 스코프가 끝날 때 여전히 해제된 메모리에 씁니다(스택은
[`07`](07-user-reported.md) J2.1 에 그대로 붙였습니다).

```cpp
// 넘기기 직전에 — 그 버퍼가 묶여 있으면 지금 내리고 묶음을 풉니다.
GpuAccelerator::shared().flush_resident_if(invert.image.pixels.data());
```

**규칙 ②: 버퍼를 단계에 넘겨 버릴 때는 넘기기 직전에 `flush_resident_if` 를 부릅니다.**
묶여 있지 않으면 아무 일도 하지 않으므로 상주 최적화는 그대로입니다.

### 9.2 `core/row_block_pool.cpp` — 통지를 잠금 안으로

`--pending->remaining` 뒤 **잠금 밖에서** `notify_all` 하면, 깨어난 쪽이 조건을 확인하고
스택 프레임(`PendingCounter`)을 풀어버린 뒤에 통지가 그 조건 변수를 만질 수 있습니다.
통지를 `lock_guard` 안으로 옮겼습니다.

### 9.3 크래시를 잡는 연장 (다음 사람용)

| 무엇 | 어디 |
|---|---|
| VEH 크래시 기록기 | `src/Native/abi/support/crash_log.cpp` → `%LOCALAPPDATA%\Negaflow\Logs\native-crash.txt` |
| Release 심볼 | `cmake/CompilerWarnings.cmake` — `/Zi` `/DEBUG` `/OPT:REF` `/MAP`. `/OPT:ICF` 는 **켜지 않습니다** |
| RVA → 함수·줄 | `scripts/symbolize-rva.ps1 -Rva 0x1546cb` |

### 9.4 `native.gpu_film_scan` 간헐 SEGFAULT

2026-08-19 인수인계의 "27회 중 3회 실패" 는 **2026-08-20 고침 이후 재현되지 않습니다** —
`--repeat until-fail:40` **40/40 통과**(+ 앞서 15회). 같은 원인이라고 **단정하지는 않습니다**:
상주 범위 수명 버그가 GPU 경로 전체에 걸려 있었으므로 개연성은 높지만, 실패했을 때의
스택을 잡아 두지 못했습니다. 다시 나오면 9.3 의 기록기가 이번에는 남깁니다.
