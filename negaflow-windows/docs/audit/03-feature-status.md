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
| 17 | GrainMend 자동·가이드·브러시·복제 전부 느림 | 위와 같은 원인 + GPU 없음 | **원인 확정** |

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
