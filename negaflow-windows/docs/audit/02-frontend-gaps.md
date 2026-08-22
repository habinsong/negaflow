> # 하드코딩 · 가짜 구현 · 창작 · 병신 백엔드 · 병신 프론트엔드 = 죽음
>
> ** 추측·가설 금지.** "냄새난다" 고 덮지 말고 **냄새의 원인을 찾아 없애십시오.**
> 재현하고, 스택을 잡고, 계측해서 원인을 **확정**한 뒤에 고칩니다.
> 원인을 못 잡았으면 **"못 잡았다" 고 적으십시오** — 추측으로 고친 것은 다음 사람의 함정입니다.
>
> ** 모르면 웹 검색을 적극적으로** 하십시오 — 특히 GPU·최적화·UI/UX 구현. 찾은 것은 출처를 남기십시오.
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


# 02 — 프론트엔드 감사 (3뷰)

macOS `Sources/negaflowApp/Features/` **529파일**을 Windows `src/Shell/` 과 대조했습니다.

> **사용자 판정 기준(2026-08-18):** UI/UX 가 구현돼 있으면 둘 중 하나다 —
> ① 위치·크기·모양·색상·정렬이 틀렸다 ② **백엔드 로직이 없다(가짜 UI)**.

> **2026-08-20 세션 갱신 요약.** 닫은 것: 폴더 일괄 적용(값만 쓰고 재현상 안 하던 가짜 UI,
> 2.2) · 스캐너 세션 공유(2.3) · 부분 보정 신규 구현(2.4b, 이전엔 완전히 없었음) · 빠른
> 내보내기 무동작 버그 둘(현상뷰·인화뷰, 2.5) · 컬러 믹서/그레이딩 캡슐·캘리브레이션
> 묶음·스캔 IR줄·프레임찾기 색·편집 회전 표시(3절) · 평판/필름 UI 차이 회귀 시험(5절).
> **여전히 남음:** 좌측 세로 레일 자체(라이브러리 3·현상 6·인화 4 항목, 2.3) · 라이브러리
> 뷰 22개 중 대부분(2.2) · 인화 뷰 7개(2.4) · 내보내기 35파일(2.5, 배치/저널/검증) ·
> 부분 보정 캔버스 그리기 앱 실측 · 설정/디스크/캐시 UI(9·10). 전부 단위시험은
> 통과했으나(shell 1499 assertions) **화면 실측은 이 세션에서 하지 않았습니다** —
> computer-use 를 쓰지 않았고 스크린샷 대조와 코드 대조로만 판정했습니다.

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
| `CanvasCompareControls.swift` | 197 | `CanvasCompareHud` + `CanvasCompareState` (2026-08-19). Before 소스 메뉴 남음 |
| `CanvasCompareDivider.swift` | 166 | `CanvasCompareDividerState` + 선/손잡이 (2026-08-19) |
| `CanvasViewportState.swift` | 71 | `CanvasViewportState` + `CanvasViewportGeometry` (2026-08-19) |
| `CanvasToolHUD.swift` | 98 | `CanvasToolHud` 단추·퍼센트·끌기 (2026-08-19) |
| `CanvasHUDLayer.swift` | 39 | 일부 |
| `CanvasHUDPlacement.swift` | — | `CanvasHudPlacement` + `CanvasHudInteractionState` |
| `CanvasScrollPanBridge.swift` | — | **없음** |
| `CanvasView+Comparison.swift` | — | **없음** |

**비교 캡슐·분할 클립·HUD 끌기·Before 소스(MAIN/무보정/원본/`frame:`)는 2026-08-19 붙임.**
무보정 Before 는 `ExportFlatMaster.Neutralize` 로 한 번 더 현상합니다.
줌 HUD 는 `CanvasToolHud`(− / % / 맞춤 / +) + `CanvasViewportState`.
앱에서 Before 메뉴 클릭·인화 HUD 위치는 실측이 남음.

### 2.2 라이브러리 뷰 — macOS 22개 중 없는 것

| macOS | Windows |
|---|---|
| `Filmstrip/FilmstripScope.swift` | **없음** (히트 0) |
| `Filmstrip/FrameStepButton.swift` | **없음** (히트 0) |
| `FrameRenameSheet.swift` | **없음** (히트 0) |
| `LibraryCompareView.swift` | 파일명 히트 0. **훑어보기 모드는 있음** — `LibraryCullingMode.Compare`/`Survey` + 단축키 C/N |
| `LibraryFolderDevelopmentControls.swift` | **2026-08-20 붙음, 같은 날 재현상 버그 고침.** 처음 붙인 판은 카탈로그 값만 쓰고 다시 현상하지 않아 **적용을 눌러도 썸네일·현상뷰가 옛 그림 그대로**였습니다(macOS `applyLibraryFolderDevelopment` 는 값을 쓴 뒤 `developFrame(preserveThumbnail:false)` 로 프레임마다 다시 현상). `ThumbnailService.RerenderAsync`(디스크 캐시를 보지 않고 무조건 다시 그림) + `LibraryFolderDevelopment.ApplyAsync`(값 먼저 쓰고 재현상, 진행률은 실제 현상 완료 기준) 로 고침. `LibraryWorkspaceView.FolderDevelopmentApplied` 로 현상뷰·인화뷰도 다시 맞춥니다. 폴더 머리줄 여백(`.padding(6)`+첫 폴더만 위 0)·제목 13pt·장수 12pt monospaced 도 이날 수치 교정. 시험 7개(`LibraryFolderDevelopmentTests`). 앱 실측은 아직 |
| `LibraryOrganizerSection.swift` · `LibraryOrganizerNameSheet.swift` | **없음** (히트 0) |
| `LibraryStackBadge.swift` · `LibraryStackMenu.swift` | 히트 2 (거의 없음) |
| `LibraryFrameContextMenu.swift` | 히트 1 (거의 없음) |
| `LibraryBrowserHeader.swift` | 히트 1 |
| `FilmstripSizing.swift` | 히트 1 |
| `HorizontalFilmstripWheelBridge.swift` | **없음** |

### 2.3 좌측 세로 레일 — 가짜 분리

Windows `src/Shell/Views/Library/Host/LibrarySourceRail.cs:74-76` 이 내는 것은 **3개뿐**입니다.

```
ImportRailButton → LibrarySourceKind.Importing
FilesRailButton → LibrarySourceKind.Files
CollectionsRailButton → LibrarySourceKind.Collections
```

macOS 는 `WorkflowSidebar.swift` + `SidebarViews.swift` + `WorkspacePresentationStore.sidebarTab`
로 탭 상태를 **저장까지** 합니다(`workspace.sidebarTab` 키). Windows 의 레일은 아이콘만
세로로 놓았을 뿐, 탭마다 들어갈 내용·상태 저장·macOS 와 같은 아이콘/선택 표시가 없습니다.

**판정: 위치·크기·모양이 macOS 와 다르고, 탭 안의 기능이 비어 있습니다(②번). 세로 레일 자체(라이브러리 3·현상 6·인화 4 항목)는 이번 갱신에서도 그대로 남았습니다 — 아래는 그 레일이 공유하는 상태 하나만 고친 것입니다.**

**2026-08-20 붙음 — 스캐너 세션 공유.** macOS 는 `AppModel` 하나가 스캐너 세션과
`showScannerControls` 를 들고 라이브러리·현상 사이드바가 같은 것을 냅니다. Windows 는
`LibraryScanPanel` 을 두 벌 만들어 각자 `ScanSessionController` 를 새로 만들었고, 현상뷰
쪽 세션은 아무도 열지 않아 **현상뷰 좌측탭 스캔 구획이 항상 비어 있었습니다.**
`ScanSessionHost` 를 신설해 `WorkspaceShellView` 가 한 벌만 만들고 두 사이드바에 물립니다.

> **2026-08-20 사용자 지시(다시 열림).** "라이브러리/현상뷰/인화뷰의 좌측탭(좌측탭에 있는
> 왼쪽 세로탭바 포함, 세로탭바의 기능별 UI/UX 및 백엔드 포함) 과 우측탭, 상단탭 모두
> 제대로 UI/UX 와 백엔드 구현해라." — 세 뷰 전부입니다. 대조할 스크린샷:
> `라이브러리뷰_좌측탭_세로탭_컬렉션.png` · `..._파일트리뷰.png` ·
> `현상뷰_좌측탭_세로탭_{필름,프리셋,프리셋(디지털),버전,파일구조,내보내기}.png` ·
> `인화뷰_좌측탭_세로탭_내보내기.png` — 즉 macOS 세로 레일 탭은
> **라이브러리 3 · 현상 6 · 인화 4** 이고 Windows 는 라이브러리 3개만 냅니다.

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

### 2.4b 부분 보정(Local Adjustments) — **2026-08-20 신규 구현, 이전에는 완전히 없었음**

macOS `Features/Develop/LocalAdjustments/` 6파일(`LocalAdjustmentSection`·`Overlay`·
`Session`·`MaskFactory`·`MaskSupport`·`AppModel+LocalAdjustments`) 대응 코드가 Windows 에
**하나도 없었습니다**(카탈로그 모델 `LocalDodgeBurnAdjustment` 만 있고 UI·백엔드 0).
이날 전부 새로 옮겼습니다:

| macOS | Windows |
|---|---|
| `LocalAdjustmentSession` | `LocalAdjustmentSession`(Shell.Core) — 마스크 종류·닷지/번·양 0.35·페더 0.20·브러시 0.04 초기값, `toggleDrawing` |
| `AppModel+LocalAdjustments` (add/update/remove/undo) | `LocalAdjustmentEditing` + `DevelopPanelState.EditLocalDodgeBurn` |
| `LocalAdjustmentMaskFactory` | `LocalAdjustmentMaskFactory` — 브러시 굵기 0.005–0.25 클램프, 방사형 반지름은 원본 크기를 알면 짧은 변 기준 |
| `LocalAdjustmentOverlay`(끌기 상태) | `LocalAdjustmentDraft` + `DevelopLocalAdjustmentCanvasInput` — 브러시는 2pt 문턱마다 점을 쌓고, 방사형·선형은 시작/끝 두 점만, 다각형은 눌러서 꼭짓점 찍기 |
| `LocalAdjustmentSection` 카드(마스크 4칸·모드 캡슐·양/페더/크기·목록) | `DevelopLocalAdjustmentSection.xaml` + `DevelopLocalAdjustmentRows` |
| `promptBar`(그리는 동안 안내 캡슐 + 다각형 완료 단추) | `DevelopPreviewCanvas` 의 `LocalAdjustmentPrompt` |

시험 24개(`LocalAdjustmentTests`) — 세션 초기값·그리기 토글·복사/붙여넣기(새 id)·목록
편집·페더 환산·마스크 팩토리 클램프·드래프트. **캔버스에서 실제로 그려서 마스크가 눈에
보이는지, 목록 줄 UI가 스크린샷과 맞는지는 앱 실측이 아직입니다.**

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

**2026-08-20 버그 둘 고침(가짜 UI였음).** ① `DevelopExportPanel.OnQuickExportClicked` 가
`RunQuickExport` 대리자를 꽂아 준 화면에서만 동작했는데, **인화뷰 좌측 내보내기 탭은 그
대리자를 꽂지 않아 빠른 내보내기 단추를 눌러도 아무 일도 없었습니다.** 패널 스스로
`DevelopExportRunner.RunQuickExportAsync()`(macOS `quickExportSelection()` 과 같은 규칙 —
사이드카·무보정본·원본 사본을 안 남기고 이름 규칙 기본값 고정, 선택 여러 장이면 배치)
를 기본 동작으로 갖게 해 대리자가 없어도 동작합니다. ② 인화뷰는 `PrintExportPanel.Attach`·
`ApplyPreferences` 를 부르지 않아 이 탭에서 고친 형식·폴더·DPI 가 **저장되지 않고 현상뷰와
다른 값을 보였습니다** — `PrintWorkspaceView` 가 상태를 물리도록 고침.
**단추 모양**도 macOS `ExportActionPill`(강조색 20% 바탕 + 강조색 글자, 라운딩 15/12,
오른쪽에 폴더 열기 원형 단추)로 바꿨습니다 — 전에는 WinUI 기본 `AccentButtonStyle` 꽉
채운 단추였습니다. 시험 5개(`ExportConfigurationTests.VerifyQuickExportBatchSettings`).

### 2.6 GrainMend IR — 5번째 단추가 아니라 짝짓기

`DevelopGrainMendPanel` 도구 단추는 **4개**입니다. **Swift 도 5번째 IR 단추가 없습니다.**
macOS 는 `InfraredImportPairing` + 선택 시 `runInfraredCleanIfNeeded` 입니다.

**2026-08-19 붙음:** `InfraredFilmCompatibility` · `InfraredImportPairing` ·
`InfraredCleanPolicy` · 선택/`SetSelection` 에서 `TryInfraredCleanIfNeeded`.
스캔 publish 는 이미 IR 을 돌립니다.

앱에서 IR 쌍을 가져와 레이어가 생기는지, 기존 장에 IR 만 붙이기는 **못 쟀습니다.**

---

## 3. UI 는 있는데 백엔드가 없거나 안 붙은 것 (가짜 UI)

| 표면 | 증상 | 확인한 것 |
|---|---|---|
| **현상 프로세스·타깃 (MAIN·HS·SP·F135·HR)** | **2026-08-20 닫음** | 현상 뷰 좌측탭(라이브러리 탭)의 `LibraryDevelopDefaultsPanel` 이 macOS `DevelopDefaultsSection` 자리입니다. 이날 ① 타깃 막대를 macOS `SegmentedPicker` 판형으로 바꾸고 ② 값이 바뀌면 구획을 다시 읽게 하고 ③ `DevelopDefaultsChanged` 를 `DevelopInspectorSync` 가 받아 프레임을 다시 읽고 프리뷰를 다시 걸게 했습니다. UIA 로 MAIN→HS→SP→F135→HR 전환·필름 프로파일 추종·메뉴 체크까지 확인 — [`07`](07-user-reported.md) K2 |
| **필름 프로필 / 룩** | 작동 안 함 | `DevelopFilmLookPanel.xaml.cs` 는 붙어 있으나 사용자 확인 결과 반영 안 됨. 슬라이더 눈금 문제(아래)와 겹칠 가능성 |
| **우측 인스펙터 슬라이더 전체** | 1씩만 움직임이었음 | **2026-08-18 0.01 로 고침** |
| **슬라이더 값 직접 입력** | 숫자 눌러도 입력 안 됨이었음 | **2026-08-18 고침** |
| **톤 곡선** | 작동 안 함 | 네 축 슬라이더가 `InspectorSlider` 라 위 눈금 문제 직격(범위가 ±작은 값이면 정수 스냅으로 **양 끝만** 잡힘). 점 커브 엔진(`point_curve.cpp`)은 macOS 와 일치 |
| **정렬 방향(오름/내림)** | 토글 없음 | `SortDirection` 히트 3, `Ascending`/`Descending` 12/10 — 상태는 있으나 macOS 의 토글 UI 없음 |
| **상단바 별점·플래그·거부** | 없음 | `Rating` 39 · `Flag` 78 · `Reject` 50 히트는 라이브러리 쪽. **현상 상단바에 없음** |
| **상단바 `프리뷰 스캔`·`사진 스캔`** | 없음 | `PreviewScan` 히트 8(macOS 64), `ScanPhoto` 히트 **0** |
| **상단 중앙 사진 번호** | 파일명이 나옴 | `PhotoNumber` 히트 2. macOS `AppModel+PhotoNumbering.swift` 대응 없음 |
| **폴더 일괄 적용** | **2026-08-20 닫음** | 값만 쓰고 재현상을 안 해 썸네일·현상뷰가 안 바뀌던 것. 위 2.2절 |
| **현상뷰 빠른 내보내기** | **2026-08-20 닫음** | 캔버스 위 상태 줄에만 적고 여러 장 선택 시 한 장만 나가던 것 |
| **인화뷰 빠른 내보내기** | **2026-08-20 닫음** | 대리자가 없어 단추를 눌러도 무동작이던 것. 위 2.5절 |
| **컬러 믹서 캡슐·컬러 그레이딩 캡슐** | **2026-08-20 닫음** | 라디오 동그라미 4개였던 것을 macOS `CapsuleSegmented`(칸 24·사이 2·여백 2·12%/5%)로. `NegaflowCapsuleSegmentStyle` 신설 |
| **캘리브레이션 원색 3묶음** | **2026-08-20 닫음** | 전부 평평한 `Spacing=10` 이던 것을 원색별 `VStack(spacing:4)`+구분선 `opacity(0.35)` 로 |
| **스캔 IR·시뮬레이터 줄** | **2026-08-20 닫음** | `ToggleSwitch.Header`+켬/끔 글자로 두 줄이던 것을 macOS `Toggle(제목, isOn:)` 한 줄로 |
| **스캔 프레임 찾기(자동/수동) 색** | **2026-08-20 닫음** | 중립 세그먼트였던 것을 AppKit 기본 `.pickerStyle(.segmented)` 강조색으로(`NegaflowAccentSegmentStyle`) |
| **편집 카드 회전/뒤집기 표시** | **2026-08-20 닫음** | 머리줄 오른쪽 `180` 같은 표시가 없던 것을 `ImageTransformRecipe.DisplayName` 추가로 |

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

**9건은 2026-08-19 에 고쳤습니다.** `B&amp;W` 와 `{0} 사본 %d` 는 오류가 아니었습니다
([`06`](06-false-claims.md) 15.2 · [`07`](07-user-reported.md) F).

**2026-08-20: 전수 대조를 했습니다.** `scripts/compare-mac-strings.py` 가 resw 주석이
가리키는 Swift 심볼을 macOS 표에서 찾아 6개 언어를 통째로 비교합니다 —
**2,670건 중 다른 것 0**, OS 강제 예외 24건(Finder→파일 탐색기, ⌥→Alt, `%@`→`{0}` 등).
같은 날 **설정에서 언어를 바꿔도 안 바뀌던 원인 셋**도 고쳤습니다.
상세 [`18`](18-localization.md). `sync-swift-ui-strings.ps1` 은 여전히 돌리지 마십시오
(그 스크립트는 문구를 **덮어씁니다**).

### 4.0 세그먼트 컨트롤 — 2026-08-20 다시 짬

macOS `Shared/UI/SegmentedPicker.swift` 를 그대로 옮겼습니다: 트랙 라운딩 **11** ·
여백 **3** · 칸 사이 **3** · 칸 높이 **28** · 고른 칸 라운딩 **8** · 트랙 바탕
`Color.primary.opacity(0.07)`. Swift 에 마우스 올림 상태가 없어 만들지 않았습니다.
판형은 `src/Shell/Styles/Segments.xaml`. 쓰는 곳: 현상 타깃 다섯 칸,
필름 베이스 모드 세 칸. 이전 판은 낱개 단추(간격 4 · 파란 배경)라 모양이 달랐습니다.

### 4.1 빠른 동작 알약 — 2026-08-20 다시 짬

자동 색상·자동 레벨(토글)·자동 톤·자동 화이트 밸런스(동작+되돌리기) 네 알약을
macOS 구조 그대로 다시 만들었습니다. WinUI 기본 `ToggleButton` 판형이 켜짐에
ContentPresenter 를 강조색으로 꽉 칠해 **글자가 안 보이던 것**이 원인이었습니다.
판형은 `src/Shell/Styles/Pills.xaml`. 상세 [`07`](07-user-reported.md) J1.

---

## 5. 스캐너

| 증상 | 확인한 것 |
|---|---|
| **DPI·심도·프레임 규격을 고르면 앱 종료** | **2026-08-18 고침.** 열린 ComboBox 에서 `Items.Clear()` 가 원인이었음. 목록이 같으면 지우지 않음([`07`](07-user-reported.md) A2) |
| **플러그인 로딩 자체가 안 됨** | `Shell.Core/Scanner/` 에 20개 파일(Discovery·ProcessHost·Protocol·TrustStore)이 있습니다. 동작 확인 안 했습니다 |
| 프레임 규격 행 | `ScanFrameFormatRow` 가 `Visibility="Collapsed"` 로 시작(128행) — 언제 켜지는지 확인 필요 |
| **평판(Epson V700/GT-X900) vs 필름(OpticFilm 8100) UI 차이** | **2026-08-20 회귀 시험으로 고정.** 차이는 `UsesFlatbedRegionWorkflow`·`AvailableFrameFormats` 두 값뿐 — 평판은 프레임 규격·찾기(자동/수동)·선택 줄이 있고 "사진 수" 줄이 없음, 필름기는 반대. `ScanSessionTests.VerifyFlatbedVersusFilmScannerUi` 로 두 갈래 다 확인. **UI 는 앱에서 실측 안 함**(단위시험만) |
| **스캐너 세션이 라이브러리뷰·현상뷰에서 따로 놀던 것** | **2026-08-20 닫음.** `ScanSessionHost` 로 한 벌 공유. 위 2.3절 |
| **스캔 폴더 선택** | **2026-08-20 신규.** macOS `chooseScanStorageRoot()` — `ScanSessionController.ScanStorageRoot` + 폴더 고르개 단추. 전에는 라이브러리 루트 아래 `Scans` 고정이었음 |
| **스캔 중 취소** | **2026-08-20 신규.** macOS `if model.isScanning { 취소 }` — 스캔 버튼 자리가 취소로 바뀜. 전에는 취소 방법이 없었음 |
