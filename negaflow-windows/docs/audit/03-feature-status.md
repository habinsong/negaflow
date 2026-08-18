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


# 03 — 기능 단위 상태

사용자가 2026-08-18 에 직접 짚은 것 + 코드 대조로 확인한 것입니다.
**"확인함"은 파일과 줄 번호를 적었습니다. 못 잡은 것은 못 잡았다고 적었습니다.**

---

## 1. 사용자가 보고한 증상 → 코드에서 확인한 원인

| # | 증상 | 원인 (확인함) | 상태 |
|---|---|---|---|
| 1 | 우측탭 슬라이더가 **1씩** 움직임 | `Views/Controls/InspectorSlider.xaml` 에 `StepFrequency` 미지정 → WinUI 기본 **1**, `SnapsTo` 기본 StepValues. macOS 는 `Slider(value:in:)` 에 `step:` 없음 = 연속 | **고침(0.01)** |
| 2 | 숫자 눌러도 **입력·Enter·ESC 안 됨** | `InspectorSlider.xaml.cs BeginEditing()` 이 TextBox 를 막 `Visible` 로 바꾼 **같은 틱에** `Focus()` 호출 → 배치 전이라 실패 → 포커스가 방금 접은 단추를 떠나 슬라이더로 감. `IsTabStop="False"` 도 겹침 | **고침** |
| 3 | **톤 곡선 작동 안 함** | 네 축이 `InspectorSlider` 라 #1 직격. 범위가 ±작은 값이면 정수 스냅으로 **양 끝만** 잡힘. 점 커브 엔진 자체(`point_curve.cpp`)는 macOS 와 일치 | #1 고침으로 해소 예상, **미검증** |
| 4 | **현상 타깃 MAIN·HS·SP·F135·HR 선택 안 됨** | 타깃 바가 `Views/Library/Defaults/LibraryDevelopDefaultsPanel.xaml.cs:61` 에**만** 있음. 현상 뷰는 `DevelopWorkspaceView.xaml.cs:305` 에서 **읽기만** 함 | **미수정** |
| 5 | **필름 프로필·룩 작동 안 함** | `DevelopFilmLookPanel.xaml.cs:74-88` 은 붙어 있음. #1 과 겹칠 가능성(강도 슬라이더) | **원인 미확정** |
| 6 | 오탈자 `타깋` `룹` | `ko-KR/Resources.resw:1066,1068`. macOS 원문은 `타깃`·`룩` | **미수정** |
| 6.5 | **필름 베이스 수동 — 베이스 스포이드 없음** | macOS `FilmBasePicker.swift`(149줄) + 캔버스 오버레이 + 인스펙터 캡슐이 전부 없었음. 수동 모드에서 베이스를 집을 유일한 수단 | **2026-08-18 이식함**(`d39e55e`). **C1.9** RealScan 리베이트 클릭 → Dmin `0.40 0.13 0.07`, 헤더·현상본 유지. 장면 클릭은 Dmin 유지 |
| 6.6 | **필름 베이스 자동 — 창작 관문** | `connected_component_base` 의 `candidate_peak` 게이트가 macOS 에 없는 것 | **2026-08-18 제거함**(`cfd5e88`). 죽은 코드였음 — 17장 dmin **바이트 동일** |
| 7 | **스캐너에서 DPI·심도·프레임 규격 고르면 앱 종료** | `LibraryScanPanel.xaml` 92·122·135행 셀렉터의 `SelectionChanged` | **종료 지점 미확인** |
| 8 | **스캐너 플러그인 로딩 자체가 안 됨** | `Shell.Core/Scanner/` 20파일 존재. 동작 미확인 | **미확인** |
| 9 | **비교 캡슐(원본/현상본/좌우/상하) 없음** | macOS `CanvasCompareControls.swift`(197줄)·`CanvasCompareDivider.swift`(166줄) 대응 **히트 0** | **없음 확정** |
| 10 | **줌 HUD 없음** | `ZoomLevel`·`ZoomIn`·`ZoomOut`·`FitToWindow` 히트 **0**. macOS `CanvasViewportState.swift` 대응 없음 | **없음 확정** |
| 11 | **좌측 세로 레일이 가짜** | `LibrarySourceRail.cs:74-76` 이 내는 것은 3개(Import·Files·Collections). macOS 는 `WorkflowSidebar` + `WorkspacePresentationStore.sidebarTab` 저장까지 | **없음 확정** |
| 12 | **내보내기·빠른 내보내기 부실** | macOS Export **41파일 7,034줄** → Windows **6파일**. 배치·체크포인트·저널·트랜잭션·검증등급 전부 없음 | **없음 확정** |
| 13 | **GrainMend IR 프론트 없음** | `DevelopGrainMendPanel.xaml` 도구 단추 4개(자동·가이드·브러시·복제). **IR 단추 없음** | **없음 확정** |
| 14 | **초기화(모든 보정·사진 각도) 없음** | macOS `Tools/ResetControlsSection.swift:14,23` 의 `onResetAllAdjustments`·`onResetPhotoAngle` 두 단추. Windows `ResetAllAdjustments`·`ResetControlsSection`·`InspectorResetter`·`ResetAngle` 전부 히트 **0**. macOS `DevelopInspectorResetter.swift`(104줄) 대응 없음 | **없음 확정** |
| 15 | **인화 프리뷰가 저해상도 썸네일이라 깨짐** | `Views/Print/Preview/PrintPreviewRenderer.cs:323-325` 가 `thumbnails()?.TryGet(frame.Id)` → `DecodeThumbnail(jpeg)` 로 **360px 썸네일**을 그대로 확대. macOS `PrintCanvasView.swift:165-167` 은 `frame.developedImage ?? packagePreview ?? thumbnailImage` 순서로 **현상본이 먼저** | **원인 확정** |
| 16 | 프리뷰가 뭘 해도 수 초 | `run_develop` 이 호출마다 원본 디코드. 캐시 없음 | **원인 확정** |
| 17 | GrainMend 자동·가이드·브러시·복제 전부 느림 | 위와 같은 원인 + GPU 없음. 검출 8,932 ms 중 **형태학이 47%, 미세 입자까지 82%** | **원인 확정.** 계획 [`04`](04-gpu-plan.md)(무엇을) + [`13`](13-performance-playbook.md)(어떻게, vHGW 로 구조 요소 무관 O(1)) |
| 17.1 | **현상·보정·룩·인화가 느린 정확한 내역** | **아무도 안 쟀습니다.** `src/Native/pipeline/` 에 단계별 ms 계측기가 **없음**(`elapsed`·`duration_ms`·`stage_ms` 히트 0) | **미측정 — 이것이 0단계**([`13`](13-performance-playbook.md) 2절) |
| 17.3 | **GPU 착수** | `src/Native/gpu/` — D3D11 컴퓨트, FL 11_0 하한, WARP 폴백, 벤더 중립. 화소별 커널 **11개** + 이웃 원시연산 **4개**(박스·가우시안·3×3 중앙값·가이드필터) 이식, 전부 CPU 동치 `1e-5` 고정. **박스·가우시안·중앙값은 전 조건 비트 단위 일치.** **톤 단계 7/7 완주**(우측 인스펙터 경로 전체) + **`filmScanShrink` 전 사슬**(`apply_film_scan_denoise` 와 직접 대조, CPU 와 같은 512/18 타일로 1.2e-07) | **2026-08-18.** 상세는 [`04`](04-gpu-plan.md) 0절 |
| 17.4 | **GPU 가 아직 아닌 것** | ① 파이프라인 미연결(`stages/look.cpp`·`stages/finish.cpp` 는 CPU 만 부름) ② 속도 미측정(계측기 없음) ③ 내장 GPU 실기 미확인(이 기계에 Intel/AMD 내장 없음) ④ 전송 대역폭 미측정 ⑤ `film_scan_denoise` 타일 오케스트레이터가 **시험 안에만** 있음 | **정직하게 미완** |
| 17.5 | **GPU 가 재서 확정한 제약 둘** | ① 러닝 섬을 쓰는 단계는 GPU 도 **CPU 와 같은 타일**로 나눠야 값이 같습니다 — 창 밖을 안 봐도 **누적 이력**이 따라옵니다(전체 한 번에 4.3e-05, 같은 타일 1.2e-07) ② HLSL `pow` 는 `std::pow` 와 **마지막 비트가 같을 수 없고**(D3D11 이 `log2`·`exp2` 에 2^-21 허용), 가이드 필터의 `1/(variance+ε)` 이 그 1 ulp 를 2e-05~6e-05 로 키웁니다 | [`13`](13-performance-playbook.md) 15·16절 |
| 17.2 | **CPU 쪽 안 켠 것** | SIMD 히트 11개 전부 `flatbed_frame_*`(화소 경로 0) · 스레드 풀 없음(`parallel_rows.cpp:113` 호출마다 `std::thread`) · `/arch:`·`/GL`·`/LTCG` 없음(`/fp:precise` 는 `cmake/CompilerWarnings.cmake:12` 에 있음) | **실측 확인**([`13`](13-performance-playbook.md) 1·3절) |

---

## 2. 없는 기능 — 확정 (히트 0)

### 2.1 현상 뷰 우측 인스펙터

| macOS | 줄 | Windows |
|---|---:|---|
| `Tools/ResetControlsSection.swift` | 44 | **없음** — 모든 보정 초기화 / 사진 각도 초기화 |
| `DevelopInspectorResetter.swift` | 104 | **없음** — 섹션별 초기화 로직 |
| `DevelopInspectorKeyboardController.swift` | — | **없음** |
| `DevelopInspectorProfileMatcher.swift` | — | **없음** |
| `Histogram/InteractiveHistogramView.swift` | — | **없음** — 히스토그램은 그리지만 상호작용 없음 |
| `Tools/DefectControlsSection.swift` | — | **없음**(히트 0) |
| `Develop/DevelopHistory.swift` + `AppModel+DefectHistory.swift` | 228 | **없음** — **undo/redo 자체가 없음** |

### 2.2 캔버스

| macOS | 줄 | Windows |
|---|---:|---|
| `CanvasCompareControls.swift` | 197 | **없음** |
| `CanvasCompareDivider.swift` | 166 | **없음** |
| `CanvasViewportState.swift` | 71 | **없음** |
| `CanvasHUDPlacement.swift` | — | **없음** |
| `CanvasScrollPanBridge.swift` | — | **없음** |
| `CanvasView+Comparison.swift` | — | **없음** |

### 2.3 라이브러리

`FilmstripScope` · `FrameStepButton` · `FrameRenameSheet` · `LibraryCompareView` ·
`LibraryFolderDevelopmentControls` · `LibraryOrganizerSection` · `LibraryOrganizerNameSheet` ·
`HorizontalFilmstripWheelBridge` — 전부 히트 0.

### 2.4 인화

`PrintCustomPackageCanvasOverlay` · `PrintLayoutTemplateControls` · `PrintLayoutTemplateStore` ·
`PrintPackageArtifactLayout` · `PrintPackageCaptionFormatter` · `PrintSettingsHistory` ·
`PrintWorkspaceSidebar` · `RenderManifestArtifactInspector` — 전부 없음.

### 2.5 내보내기

배치 4파일 · 체크포인트 2파일 · 커밋 저널 3파일 · 트랜잭션/쓰기 3파일 · 검증등급 ·
Reveal · 가용성 스토어 · 소스 실체화 · 추적 이벤트 · UI 7파일 — 전부 없음.

---

## 3. 썸네일

| | macOS | Windows |
|---|---|---|
| 크기 | `thumbnailMaxDimension = 360` | `ThumbnailService.MaximumDimension = 360` ✔ |
| 언제 만드나 | 정착 패스마다 현상 결과로 덮어씀 (`AppModel+DevelopRendering.swift:236`) — 인터랙티브 패스는 건너뜀 → 디스크 IO 는 정착 1회 | 정착 패스 자체가 없음 |
| 네거티브 최초 | 빠른 포지티브 썸네일 → 정착 결과로 교체 (`AppModel+Develop.swift:111`) | 대응 없음 |
| 인화 뷰에서 | **현상본 우선**, 썸네일은 최후 폴백 | **썸네일만** 씀 → 확대하면 깨짐 |

---

## 4. 창작 (macOS 에 없는데 Windows 가 지어낸 것)

| 항목 | 상태 |
|---|---|
| `DefectOverlayImage` 의 `Opacity="0.75"` | **제거함(2026-08-18).** macOS 는 불투명도를 색마다 넣음 |
| 하단바 `ABI 0.48 · X64` | 제거함(`f5d9a5b`) |
| GrainMend 캡슐 `CornerRadius="999"` | 수정함(`f5d9a5b`, 18/15) |
| `muted_scene_vibrance_table.cpp` 9,003줄 | **창작 아님.** macOS `CIFilter("CIVibrance")` 는 Apple 비공개 커널이라 33³ LUT 로 측정 이식. golden 해시 문서 있음 |

---

## 5. 아직 원인을 못 잡은 것 (정직하게)

1. 스캐너 DPI/심도/프레임규격 선택 시 **앱 종료** — 재현 후 스택 필요
2. 스캐너 플러그인 로딩 실패 — 로그 필요
3. 필름 프로필·룩이 안 먹는 정확한 이유 — 슬라이더 눈금 문제 고친 뒤 재확인 필요
4. 복제 도장 칩을 눌러도 캔버스 컨트롤 바가 안 뜨는 이유 — 클릭 미도달인지 버튼 비활성인지 미확정
