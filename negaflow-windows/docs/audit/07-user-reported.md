> # ⛔ 창작 금지
>
> **macOS Swift 파일을 먼저 열고, 코드를 1:1 로 그대로 옮깁니다.**
> 설명만 보고 다시 쓰지 마십시오. 상수 하나, 임계 하나, 게이트 순서 하나도 지어내지 마십시오.
> 이름이 같다고 "있음" 으로 적지 마십시오 — **함수 안을 읽고** 판정하십시오.
> 전체 규칙은 [`00-index.md`](00-index.md) 맨 위에 있습니다.

---

# 07 — 사용자 실사용 보고 (2026-08-18)

사용자가 앱을 직접 쓰면서 보고한 것 전부입니다. **하나도 빼지 않았습니다.**
각 항목마다 코드에서 확인한 것과 **아직 확인 못 한 것**을 나눠 적었습니다.

---

## A. 앱이 터지는 것 (최우선)

| # | 증상 | 확인한 것 | 상태 |
|---|---|---|---|
| A1 | **설정 버튼 누르면 앱 터짐** | `src/Shell/SettingsWindow.xaml(.cs)` + `Views/SettingsRootView.xaml(.cs)` + `.ScanTab.cs` + `.Shortcuts.cs` 존재 | **스택 미확인** |
| A2 | **스캐너에서 DPI·심도·프레임 규격 고르면 앱 종료** | `Views/Library/Scanner/LibraryScanPanel.xaml` 92행 `ScanResolutionSelector` · 122행 `ScanBitDepthSelector` · 135행 `ScanFrameFormatSelector`, 각각 `SelectionChanged` | **스택 미확인** |

**둘 다 재현 후 예외 스택을 잡아야 합니다.** 추측으로 고치지 않습니다.

---

## A.1 함정 — 새 문서가 커밋되지 않습니다

`.gitignore:112` 에 `/negaflow-windows/docs/` 가 있습니다. `docs/plan/`·`docs/progress/` 의
기존 파일은 무시 규칙보다 먼저 추적돼 살아남았지만, **새로 만든 문서는 조용히 빠집니다.**
이 감사 문서도 `git add -f` 로 넣어야 했습니다.

**고칠 것**: 규칙을 좁히거나(`/negaflow-windows/docs/generated/` 등) 예외를 두어야 합니다.
지금 상태로는 핸드오프를 써도 저장소에 남지 않습니다.

---

## B. 메뉴막대 — **통째로 없음**

macOS `App/AppMenuCommands.swift` · `AppStandardMenuCommands.swift` · `AppWorkflowMenuCommands.swift`
세 파일이 메뉴막대를 냅니다.

| macOS 메뉴 | 정의 위치 | Windows |
|---|---|---|
| negaflow에 관하여 / 설정 | `AppStandardMenuCommands.swift:10` (`.appInfo`) | **없음** |
| 파일 | `:16` (`after: .newItem`), `:38` (`after: .importExport`) | **없음** |
| 편집 | `:54` (`replacing: .undoRedo`), `:66` (`.pasteboard`), `:78` (`.textEditing`) | **없음** |
| 보기 | `:95` (`after: .sidebar`), `:112` (`after: .toolbar`) | **없음** |
| 라이브러리 | `AppWorkflowMenuCommands.swift:8` `CommandMenu(.menuLibrary)` | **없음** |
| 사진 | `:47` `CommandMenu(.menuPhoto)` | **없음** |
| 현상 | `:135` `CommandMenu(.menuDevelop)` | **없음** |
| 스캐너 | `:250` `CommandMenu(.menuScanner)` | **없음** |
| 내보내기 | `:292` `CommandMenu(.menuExport)` | **없음** |
| 윈도우 | 표준 | **없음** |
| 도움말 | `AppStandardMenuCommands.swift:136` (`after: .help`) | **없음** |

Windows 전 트리에서 `MenuBar` · `MenuBarItem` **히트 0**.
`Localization/Core/AppMenuCatalog.swift` 에 메뉴 문자열 카탈로그까지 있는데 대응이 없습니다.

**판정: 메뉴막대 11개가 전부 없습니다. 단축키·명령 접근 경로가 통째로 빠졌습니다.**

---

## C. 창작 판정 — macOS 와 다른 것

| # | 항목 | macOS | Windows | 판정 |
|---|---|---|---|---|
| C1 | **필름 베이스 자동/필름/수동** | `BaseControlSection.swift:20` `[.auto, .preset, .manual]` — 모드 이름은 **같음**. 엔진은 `FilmBaseEstimator` + `FilmBaseStatistics` + `FilmBaseSampleGrid` + `FilmBaseMeasurementDiagnostics` **4파일** | `BaseEstimationMode { Auto, Preset, Manual }` — 이름 같음. 엔진은 `auto_negative_base_resolver.cpp` **1파일 893줄**. `FilmBaseStatistics`·`FilmBasePicker`·`FilmBaseMeasurementDiagnostics` **히트 0** | **엔진 재작성.** 통계·진단 없이 다시 씀 → **사용자 보고: 이미지가 검게 터짐** |
| C2 | **노이즈 감소(디테일 및 효과)** | 슬라이더 5개(`strength` **0.05…1** · luma · chroma · darkTone · detail). 엔진은 `ScannerNoiseReduction.swift` + `+Color` + `+Guided` **3파일** + `Profiles/Noise` 4파일 | 슬라이더 5개 이름은 같음(`DevelopDetailSection.xaml:59-63`). **엔진 `ScannerNoiseReduction*` 히트 0**, 대신 `film_scan_denoise.cpp` 802줄. `strength` 의 `ResetValue="0"` 은 macOS 최소 **0.05** 보다 낮음 | **백엔드 창작.** UI 만 같고 엔진이 다름 |
| C3 | **좌우 뒤집기 없음** | `GeometryToolSection.swift:144` `flipHorizontal`, `:147` `flipVertical` | `DevelopGeometryCard.xaml:39` `FlipHorizontalButton`, `:40` `FlipVerticalButton` — **XAML 에는 있음** | **화면에 안 보임.** 카드가 접혀 있거나 글리프(`E7B7`/`E7B8`)가 안 그려질 가능성. **원인 미확정** |
| C4 | **각도 조절 UI 창작** | `angleDial`(`CropAngleDial`) + `angleRow`(값 + 리셋 + 슬라이더), `setStraighten` | `CropAngleDialControl` + `StraightenAngleControl`(=`InspectorSlider`) — 구조는 같음 | **눈금이 정수였음.** `InspectorSlider` 의 `StepFrequency` 미지정 → 각도가 1도 단위로만 움직임. **2026-08-18 0.01 로 고침**. 배치·모양 차이는 별도 확인 필요 |
| C5 | **컬렉션 창작** | `Features/Library/Model/Collections/` + `LibraryOrganizerSection.swift` + `LibraryOrganizerNameSheet.swift` + `LibraryOrganizerProjection.swift` | `LibraryOrganizer*` **히트 0**. 레일에 `CollectionsRailButton` 만 있음 | **UI 만 있고 뒤가 없음** |
| C6 | **스캔·스캐너 시뮬레이터** | `Features/Scanning/` 21파일 4,446줄 + `ScannerKit/` 50파일 | `Shell.Core/Scanner/` 20파일 + `Views/Library/Scanner/` 5파일 999줄 | **동작 안 함(사용자 보고).** 플러그인 로딩 자체가 안 됨 |

---

## C.1 추가 보고 (2026-08-18 후속)

| # | 증상 | 확인한 것 | 상태 |
|---|---|---|---|
| C7 | **상단탭에 필름명만 나오고 별 5개·플래그·거부 UI 없음** | `Rating`·`Flag`·`Reject` 히트는 라이브러리 쪽뿐. macOS 는 상단바에 별점·플래그·거부가 있고 상단 중앙은 **사진 번호**(`AppModel+PhotoNumbering.swift`, Windows 히트 2) | **없음 확정** |
| C8 | **상단탭 가운데 정렬이 안 맞음** | 중앙 요소가 가운데로 정렬되지 않음 | **미수정** |
| C9 | **진단 기능 미구현** | macOS `Services/Diagnostics/` **7파일**. Windows 는 `tests/Shell.UnitTests` 안의 진단 명령(`--defect-tools` 등)만 있고 **앱 안의 진단 화면 없음**. `AppModel+SupportBundle.swift`(지원 번들) 도 히트 0 | **없음 확정** |
| C10 | **모든 UI/UX 가 창작, 아이콘 없는 것도 있음** | 아이콘 macOS 117 vs Windows 56 — [`08-icons-and-chrome.md`](08-icons-and-chrome.md) | **확정** |
| C11 | **인화뷰 우측탭 전부 창작** | macOS 는 `PrintWorkspaceInspector.swift` + `PrintInspectorComponents.swift` + `PrintInspectorControls.swift` + `PrintPackageInspectorControls.swift` + `PrintLayoutTemplateControls.swift` **5파일**. Windows 는 `Views/Print/Settings/PrintInspectorBinder.cs` + `PrintInspectorSurface.cs` **2파일**뿐이고 `PrintLayoutTemplateControls`·`PrintPackageInspectorControls` 히트 **0** | **확정** |
| C12 | **인화 출력(내보내기·빠른내보내기) 백엔드·UI 틀림** | macOS 는 `AppModel+PrintExport.swift` + `AppModel+PrintPackageExport.swift` + `PrintPackageExportWriter.swift` + `PrintPackageArtifactLayout.swift` + `Chromabase/Export/PrintPackageRenderer.swift`. Windows 는 `Views/Print/Export/PrintExportWorkflow.cs` 하나. `PrintPackageRenderer` 히트 **0**, `PrintPackageArtifactLayout` 히트 **0** | **확정** |
| C13 | **자동 색상·자동 레벨·자동 톤·자동 화이트밸런스 버튼 모양 창작** | macOS `DevelopQuickActionsSection.swift`(158줄): 아이콘 `camera.filters`(자동 색상) · `chart.bar.xaxis`(자동 레벨, **토글**) · `circle.lefthalf.filled`(자동 톤) · `thermometer.medium`(자동 화이트밸런스), 각각 `Label(title, systemImage:)` + `minHeight: 32` + `.buttonStyle(.plain)` + `maxWidth: .infinity`. 맨 위에 `arrow.counterclockwise.circle` **모든 보정 초기화**(`role: .destructive`). Windows 는 GrainMend 카드 아래 텍스트만 있는 사각 단추 4개이고 **아이콘 없음**, 자동 레벨의 **토글 성격 없음**, 초기화 단추 **없음** | **확정** |

---

## D. 없는 것 (히트 0 확정)

| # | 항목 | macOS |
|---|---|---|
| D1 | **초기화 — 모든 보정 / 사진 각도** | `Tools/ResetControlsSection.swift:14,23` (`onResetAllAdjustments`, `onResetPhotoAngle`) + `DevelopInspectorResetter.swift`(104줄). Windows `ResetAllAdjustments`·`ResetControlsSection`·`InspectorResetter`·`ResetAngle` **전부 0** |
| D2 | **비교 캡슐 원본/현상본/좌우분할/상하분할** | `CanvasCompareControls.swift`(197줄) + `CanvasCompareDivider.swift`(166줄) + `CanvasView+Comparison.swift`. Windows `CompareDivider`·`compareMode`·`SplitHorizontal`·`NeutralPreview` **전부 0** |
| D3 | **줌 HUD** | `CanvasViewportState.swift`(71줄). Windows `ZoomLevel`·`ZoomIn`·`ZoomOut`·`FitToWindow` **전부 0** |
| D4 | **GrainMend IR 프론트엔드** | Windows `DevelopGrainMendPanel.xaml` 도구 단추 4개(자동·가이드·브러시·복제). **IR 없음**. 엔진 1,570줄은 있음 |
| D5 | **undo/redo** | `DevelopHistory.swift` + `AppModel+DefectHistory.swift`(228줄). Windows 는 라이브러리 undo 만 있고 현상·결함 undo **없음** |
| D6 | **내보내기 35파일** | 배치·체크포인트·커밋저널·트랜잭션·검증등급·Reveal·가용성·실체화·추적 + UI 7개 |
| D7 | **인화 8파일** | 커스텀 패키지 오버레이·레이아웃 템플릿·아티팩트 배치·캡션 포맷터·설정 이력·사이드바·매니페스트 검사 |

---

## E. 성능

| # | 증상 | 원인 (확정) |
|---|---|---|
| E1 | 사진 바꾸면 수 초 | `run_develop` 이 호출마다 `decode_source` — 5088×3401 16bit, 실측 **2,695 ms**. 캐시 **없음** |
| E2 | 우측탭 기능 하나 써도 수 초 | 같은 원인. macOS 는 프록시 캐시로 **디코드 0회** |
| E3 | GrainMend 자동·가이드·브러시·복제 전부 느림 | 위 + **GPU 코드 0줄** |
| E4 | **인화 프리뷰가 깨짐** | `Views/Print/Preview/PrintPreviewRenderer.cs:323-325` 가 **360px 썸네일**을 확대. macOS `PrintCanvasView.swift:165-167` 은 `developedImage` 먼저 |

---

## F. 문자열 오류 (macOS 원문 대조 13건 중 실오류 11건)

`타깋`→`타깃` · `룹`→`룩` · `필름스톡`→`필름 스톡` · `중간톤`→`중간 톤` ·
`Digital B&amp;W` 이스케이프 노출 · `{0} 사본 %d` 형식지정자 혼용 ·
`기본 스캔 회전`/`스캐너 성능`/`미세 반점 기본값` + 도움말 2건 macOS 원문과 다름.

---

## F.1 라이브러리 — 폴더별 현상 컨트롤

macOS `Features/Library/Views/LibraryFolderDevelopmentControls.swift` **224줄**:

| 줄 | 요소 |
|---:|---|
| 31 | `LibraryFolderBatchPicker` — **프로세스** |
| 40 | `LibraryFolderBatchPicker` — **타깃** |
| 49 | `LibraryFolderApplyButton` — **적용** |
| 56 | `model.applyLibraryFolderDevelopment(process:target:frames:progress:)` |

백엔드는 `Features/Library/Model/AppModel+LibraryFolderDevelopment.swift` 입니다.

Windows `Views/Library/Defaults/LibraryDevelopDefaultsPanel.xaml` 의 요소 전부:

```
DevelopDefaultsText  DevelopProcessLabel  DevelopProcessSelector
DevelopTargetLabel   DevelopTargetBar
DevelopFilmProfileLabel  DevelopFilmProfileSelector
DevelopLookLabel         DevelopLookSelector
```

**적용 단추가 없습니다.** `ApplyButton`·`applyLibraryFolder`·`ApplyToFolder` 히트 0
(있는 `*ApplyButton` 은 크롭과 브러시 것뿐). 그리고 이것은 **폴더별**이 아니라
"라이브러리 기본값" 패널입니다 — macOS 는 폴더를 골라 그 안의 프레임에 **일괄 적용**합니다.

**판정: 프론트엔드에 적용 단추 없음, 백엔드에 일괄 적용 경로 없음. 그래서 작동하지 않습니다.**

---

## G. 다음 순서 (사용자 요구 반영)

1. **A1·A2 크래시** — 스택부터
2. **E1 프리뷰 프록시 캐시 + 2단 렌더** — 슬라이더당 −2,695 ms ([`04`](04-gpu-plan.md) 3.0)
3. **C1 필름 베이스** — 검은 이미지. macOS 4파일 대조
4. **E4 인화 프리뷰** — 현상본 쓰도록
5. **B 메뉴막대 11개**
6. **D1 초기화 · D5 undo**
7. **GPU** ([`04`](04-gpu-plan.md))
8. **D2·D3 비교 캡슐·줌 HUD**
9. **D4 IR 프론트 · D6 내보내기 · D7 인화**
10. **F 문자열**
