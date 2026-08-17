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


# 02 — 프론트엔드 감사 (3뷰)

macOS `Sources/negaflowApp/Features/` **529파일**을 Windows `src/Shell/` 과 대조했습니다.

> **사용자 판정 기준(2026-08-18):** UI/UX 가 구현돼 있으면 둘 중 하나다 —
> ① 위치·크기·모양·색상·정렬이 틀렸다 ② **백엔드 로직이 없다(가짜 UI)**.

---

## 1. 규모 (실측)

| 영역 | macOS | Windows | 비 |
|---|---:|---:|---:|
| Library | 101파일 14,876줄 | 34파일 5,478줄 | **37%** |
| Print | 19파일 6,037줄 | 17파일 2,671줄 | **44%** |
| Export | 41파일 7,034줄 | 6파일 (Develop/Export) | **~15%** |
| Canvas | 22파일 2,654줄 | Develop 안에 흡수 | — |
| Develop | 68파일 8,333줄 | 89파일 12,452줄 | 149% |

---

## 2. 완전히 없음

### 2.1 캔버스 — 비교 캡슐 · 줌 HUD

macOS `Features/Canvas/` 22파일 2,654줄.

| macOS | 줄 | Windows |
|---|---:|---|
| `CanvasCompareControls.swift` | 197 | **없음** (`CompareDivider`·`compareMode` 히트 0) |
| `CanvasCompareDivider.swift` | 166 | **없음** |
| `CanvasViewportState.swift` | 71 | **없음** (`ZoomLevel`·`ZoomIn`·`ZoomOut`·`FitToWindow` 히트 **0**) |
| `CanvasToolHUD.swift` | 98 | 일부(GrainMend HUD 만) |
| `CanvasHUDLayer.swift` | 39 | 일부 |
| `CanvasHUDPlacement.swift` | — | **없음** |
| `CanvasScrollPanBridge.swift` | — | **없음** |
| `CanvasView+Comparison.swift` | — | **없음** |

**원본 / 현상본 / 좌우 분할 / 상하 분할 비교 캡슐이 없습니다.**
macOS `CanvasCompareMode` 는 `.original` · `.developed` · `.splitVertical` · `.splitHorizontal`
네 가지이고 `CanvasCompareControls.swift:130-176` 이 캡슐을 냅니다. Windows 에는 이 개념이
없습니다 — `NeutralPreview`(원본 프리뷰) 히트도 **0** 이라 비교할 원본 이미지 자체를 만들지
않습니다.

**줌 HUD 도 없습니다.** `ZoomLevel`·`ZoomIn`·`ZoomOut`·`FitToWindow` 전부 히트 0.
하단 바에 `100% ⌃` 가 보이지만 macOS 의 `− 108% +` 와 다르고, 뒤에 뷰포트 상태가 없습니다.

### 2.2 라이브러리 뷰 — macOS 22개 중 없는 것

| macOS | Windows |
|---|---|
| `Filmstrip/FilmstripScope.swift` | **없음** (히트 0) |
| `Filmstrip/FrameStepButton.swift` | **없음** (히트 0) |
| `FrameRenameSheet.swift` | **없음** (히트 0) |
| `LibraryCompareView.swift` | **없음** (히트 0) |
| `LibraryFolderDevelopmentControls.swift` | **없음** (히트 0) |
| `LibraryOrganizerSection.swift` · `LibraryOrganizerNameSheet.swift` | **없음** (히트 0) |
| `LibraryStackBadge.swift` · `LibraryStackMenu.swift` | 히트 2 (거의 없음) |
| `LibraryFrameContextMenu.swift` | 히트 1 (거의 없음) |
| `LibraryBrowserHeader.swift` | 히트 1 |
| `FilmstripSizing.swift` | 히트 1 |
| `HorizontalFilmstripWheelBridge.swift` | **없음** |

### 2.3 좌측 세로 레일 — 가짜 분리

Windows `src/Shell/Views/Library/Host/LibrarySourceRail.cs:74-76` 이 내는 것은 **3개뿐**입니다.

```
ImportRailButton      → LibrarySourceKind.Importing
FilesRailButton       → LibrarySourceKind.Files
CollectionsRailButton → LibrarySourceKind.Collections
```

macOS 는 `WorkflowSidebar.swift` + `SidebarViews.swift` + `WorkspacePresentationStore.sidebarTab`
로 탭 상태를 **저장까지** 합니다(`workspace.sidebarTab` 키). Windows 의 레일은 아이콘만
세로로 놓았을 뿐, 탭마다 들어갈 내용·상태 저장·macOS 와 같은 아이콘/선택 표시가 없습니다.

**판정: 위치·크기·모양이 macOS 와 다르고, 탭 안의 기능이 비어 있습니다(②번).**

### 2.4 인화 뷰 — macOS 19파일 중

| macOS | Windows |
|---|---|
| `PrintCustomPackageCanvasOverlay.swift` | **없음** |
| `PrintLayoutTemplateControls.swift` · `PrintLayoutTemplateStore.swift` | **없음** |
| `PrintPackageArtifactLayout.swift` | **없음** |
| `PrintPackageCaptionFormatter.swift` | **없음** |
| `PrintWorkspaceSettingsHistory` (`AppModel+PrintSettingsHistory.swift`) | **없음** |
| `PrintWorkspaceSidebar.swift` | **없음** |
| `RenderManifestArtifactInspector.swift` | **없음** |

### 2.5 내보내기 — macOS 41파일 → Windows 6파일

Windows 에 있는 것: `DevelopExportPanel.xaml(.cs)` · `DevelopExportControlSync.cs` ·
`DevelopExportCopy.cs` · `DevelopExportRecipes.cs` · `DevelopExportRunner.cs`.

**없는 것 (히트 0 또는 대응 파일 없음):**

| macOS | 하는 일 |
|---|---|
| `ExportBatchScheduler.swift` · `ExportBatchPlan.swift` · `ExportBatchStore.swift` · `ExportBatchProgressView.swift` | 일괄 내보내기 계획·스케줄·진행 표시 |
| `ExportBatchCheckpoint.swift` · `AppModel+ExportBatchCheckpoint.swift` | 중단 후 이어서 하기 |
| `ExportArtifactCommitJournal.swift`(+Async) · `ExportArtifactFileIdentity.swift` | 산출물 커밋 저널 — 무엇을 언제 냈는지 |
| `ExportFrameTransaction.swift` · `ExportFrameWriter+Commit.swift` · `+Sidecars.swift` | 프레임 단위 트랜잭션 쓰기 |
| `ExportVerificationLevel.swift` | 내보낸 파일 검증 등급 |
| `ExportRevealLocator.swift` | 낸 파일 탐색기에서 보이기 |
| `ExportAvailabilityStore.swift` | 내보내기 가능 여부 상태 |
| `ExportSourceMaterialization.swift` | 원본 실체화 |
| `ExportTrackingEventFactory.swift` | 추적 이벤트 |
| `RenderManifestArtifactInspector.swift` | 렌더 매니페스트 검사 |
| `ExportMetadataPolicyView.swift` · `ExportFormatOptionsView.swift` · `OutputSharpeningOptionsView.swift` · `ExportNamingControls.swift` · `ExportRecipeControls.swift` · `ExportActionPill.swift` · `ExportSection.swift` | 내보내기 UI 7개 |

**빠른 내보내기**: Windows 는 `QuickExportFormatSelector`·`QuickExportDpiSelector`·
`QuickExportSizeSelector`·`QuickExportJpegQualitySlider` 넷만 있습니다. macOS 의 레시피·
네이밍 템플릿·메타데이터 정책·검증 등급·저널이 전부 빠졌습니다.

### 2.6 GrainMend IR — 프론트엔드가 **아예 없음**

`DevelopGrainMendPanel.xaml` 의 도구 단추는 **4개뿐**입니다:

```
GrainMendAutoButton  GrainMendGuidedButton  GrainMendBrushButton  GrainMendCloneButton
```

**IR 단추가 없습니다.** Views 전체에서 `Infrared` 히트는 라이브러리 필터 토글과 스캔
토글뿐이고, GrainMend 카드에는 한 글자도 없습니다.

백엔드는 있습니다(`infrared_defect_detector.cpp` 1,197줄 + `defect_infrared_stage.cpp`,
합 1,570줄 / macOS 1,584줄). **엔진은 있는데 부를 화면이 없습니다.**

---

## 3. UI 는 있는데 백엔드가 없거나 안 붙은 것 (가짜 UI)

| 표면 | 증상 | 확인한 것 |
|---|---|---|
| **현상 타깃 MAIN·HS·SP·F135·HR** | 현상 뷰에서 **선택 불가** | 타깃 바는 `Views/Library/Defaults/LibraryDevelopDefaultsPanel.xaml.cs:61 BuildDevelopTargetBar()` 에만 있습니다. 현상 뷰는 `DevelopWorkspaceView.xaml.cs:305` 에서 **읽기만** 하고 설정 호출이 없습니다 |
| **필름 프로필 / 룩** | 작동 안 함 | `DevelopFilmLookPanel.xaml.cs` 는 붙어 있으나 사용자 확인 결과 반영 안 됨. 슬라이더 눈금 문제(아래)와 겹칠 가능성 |
| **우측 인스펙터 슬라이더 전체** | **1씩만 움직임** | `InspectorSlider.xaml` 에 `StepFrequency` 미지정 → WinUI 기본 **1**, `SnapsTo` 기본 StepValues. macOS 는 `Slider(value:in:)` 에 `step:` 없음 = 연속. **2026-08-18 0.01 로 고침** |
| **슬라이더 값 직접 입력** | 숫자 눌러도 입력·Enter·ESC 안 됨 | `BeginEditing()` 이 TextBox 를 막 보이게 한 **같은 틱에** `Focus()` 호출 → 배치 전이라 실패, 포커스가 슬라이더로 튐. `IsTabStop="False"` 도 겹침. **2026-08-18 고침** |
| **톤 곡선** | 작동 안 함 | 네 축 슬라이더가 `InspectorSlider` 라 위 눈금 문제 직격(범위가 ±작은 값이면 정수 스냅으로 **양 끝만** 잡힘). 점 커브 엔진(`point_curve.cpp`)은 macOS 와 일치 |
| **정렬 방향(오름/내림)** | 토글 없음 | `SortDirection` 히트 3, `Ascending`/`Descending` 12/10 — 상태는 있으나 macOS 의 토글 UI 없음 |
| **상단바 별점·플래그·거부** | 없음 | `Rating` 39 · `Flag` 78 · `Reject` 50 히트는 라이브러리 쪽. **현상 상단바에 없음** |
| **상단바 `프리뷰 스캔`·`사진 스캔`** | 없음 | `PreviewScan` 히트 8(macOS 64), `ScanPhoto` 히트 **0** |
| **상단 중앙 사진 번호** | 파일명이 나옴 | `PhotoNumber` 히트 2. macOS `AppModel+PhotoNumbering.swift` 대응 없음 |

---

## 4. 오탈자 — 한국어 문자열 macOS 원문 대조

`AppLocalizedPhrase+Korean.swift` (605구절) ↔ `ko-KR/Resources.resw` **236건 대조, 13건 불일치**.

| 키 | Windows | macOS |
|---|---|---|
| `libraryTarget.Text` | **`타깋`** | `타깃` |
| `libraryLook.Text` | **`룹`** | `룩` |
| `developFilmStock.Text` | `필름스톡` | `필름 스톡` |
| `developMidtones.Text` | `중간톤` | `중간 톤` |
| `developFilmLookDigitalOnly.Text` | `…Digital B&amp;W…` | `…Digital B&W…` (이스케이프가 화면에 그대로 나옴) |
| `namedFrameCopyDisplayFormat.Text` | `{0} 사본 %d` | `%@ 사본 %d` (**형식 지정자 혼용 — 런타임 오류 위험**) |
| `settingsDefaultScanRotation.Text` | `기본 스캔 회전` | `스캔 기본 방향` |
| `settingsDefaultScanRotationHelp.Text` | 짧게 다시 씀 | macOS 원문과 다름 |
| `settingsScannerTruth.Text` | `스캐너 성능` | `스캐너 정보` |
| `settingsMicroSpecksSection.Text` | `미세 반점 기본값` | `미세 입자 기본 검출` |
| `settingsMicroSpecksHelp.Text` | 짧게 다시 씀 | macOS 원문과 다름 |
| `libraryShowInExplorer.Content` | `파일 탐색기에서 보기` | `Finder에서 보기` — **의도적 플랫폼 차이(정당)** |
| `developGrainMendCloneSourceHint.Text` | `Alt 클릭으로…` | `⌥ 클릭으로…` — **의도적 플랫폼 차이(정당)** |

**11건이 실제 오류입니다.** 나머지 언어 5종은 같은 대조를 하지 않았습니다(macOS 표 필요).

---

## 5. 스캐너

| 증상 | 확인한 것 |
|---|---|
| **DPI·심도·프레임 규격을 고르면 앱 종료** | `LibraryScanPanel.xaml` 에 `ScanResolutionSelector`(92행) · `ScanBitDepthSelector`(122행) · `ScanFrameFormatSelector`(135행) 가 있고 각각 `SelectionChanged` 를 겁니다. **종료 지점은 아직 못 잡았습니다** — 재현 후 스택을 봐야 합니다 |
| **플러그인 로딩 자체가 안 됨** | `Shell.Core/Scanner/` 에 20개 파일(Discovery·ProcessHost·Protocol·TrustStore)이 있습니다. 동작 확인 안 했습니다 |
| 프레임 규격 행 | `ScanFrameFormatRow` 가 `Visibility="Collapsed"` 로 시작(128행) — 언제 켜지는지 확인 필요 |
