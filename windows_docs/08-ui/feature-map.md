# 기능 지도 — SwiftUI 화면 → WinUI 3

조사 2026-08-04 / 출처: `Sources/negaflowApp/` (75,913줄) 실측  
macOS 기준 커밋: `9be909c`

GUI는 **공유 0%, 전량 재작성**이다. 그러나 재작성할 제품 surface와 상태 의미는 그대로 추적한다.
이 문서는 최상위 기능 인벤토리이며, 완료 판정은 [동등성 계약](parity-contract.md), 화면별 명세와
[이행 로드맵](../99-plan/migration-roadmap.md)을 함께 사용한다.

## 규모 — 기능별

| 기능 | 줄 수 | WinUI 3 난이도 | 비고 |
|---|---|---|---|
| Library | **14,350** | 높음 | 가장 큰 덩어리. 가상화 그리드 + 트리 + 필름스트립 |
| Develop | 7,997 | 중간 | 슬라이더 인스펙터 + 톤커브 에디터 |
| Export | 7,030 | 중간 | 배치·명명 규칙·레시피 |
| Defects | 6,114 | **최상** | 브러시·복제도장·마스크 오버레이 |
| Print | 5,894 | 중간 | 레이아웃 조판 |
| Scanning | 4,335 | 낮음 | 플러그인 UI. 후속 단계 |
| Canvas | 2,630 | **최상** | SwapChainPanel + 오버레이 |
| Workspace | 1,376 | 낮음 | 레이아웃 셸 |
| Versions / Help | 241 | 낮음 | |
| **Features 합계** | **49,967** | | |
| Services | 8,754 | 중간 | 저장·캐시·모니터 |
| Localization | 7,929 | **낮음 — 자산 이관** | 6개 언어 문자열 |
| Domain / App / Settings / Shortcuts / Shared | 9,263 | 중간 | |

Localization 7,929줄의 번역 문안은 재사용 가능한 자산이지만 Swift table을 `.resw`로 기계 변환하는
것만으로 이관이 끝나지는 않는다. 변환 도구는 반복 작업을 줄이는 후보이고, 다음을 별도로 검증한다.

- interpolation과 plural/select 의미
- stable resource key와 누락 탐지
- 언어별 access key·shortcut 충돌
- 숫자·날짜·단위·파일 크기 formatting
- German/French 확장, Korean/CJK line breaking, RTL/BiDi smoke
- Narrator name/description과 technical string 비현지화

자산 이관을 초기에 시작하되 각 surface acceptance와 함께 완료한다.

## 화면별 매핑

### Workspace — 셸 레이아웃

```
SwiftUI                              WinUI 3
NavigationSplitView          →       NavigationView (좌측 사이드바)
                                     또는 자체 Grid + GridSplitter
```

Lightroom형 3분할(좌 사이드바 · 중앙 캔버스 · 우 인스펙터)이라 `NavigationView`의
기본 동작과 잘 안 맞을 수 있다. **Grid + GridSplitter로 직접 짜는 쪽이 제어가 쉽다.**

### Library — 최대 난제

실측 구성:

```
LibrarySourceSection          소스(폴더) 목록
LibraryFolderTreeView         폴더 트리
LibraryOrganizerSection       정리(컬렉션)
LibraryBrowserFilterBar       필터 바
LibraryBrowserHeader          헤더
Filmstrip/                    필름스트립 (가로 스크롤)
LibraryCompareView            비교 뷰
LibrarySurveyView             서베이(다중 비교)
LibraryCullingContent         컬링 모드
LibraryStackBadge/Menu        스택
LibraryFrameContextMenu       컨텍스트 메뉴
LibrarySourceDragAndDrop      드래그앤드롭
Duplicates/                   중복 탐지
Recovery/                     복구
```

| SwiftUI | WinUI 3 | 주의 |
|---|---|---|
| `LazyVGrid` 썸네일 그리드 | **`ItemsView` + `UniformGridLayout`** | `GridView`(구형)가 아니라 `ItemsView`. 가상화 성능이 다르다 |
| `OutlineGroup` 폴더 트리 | `TreeView` | 항목 수천 개면 지연 로딩 필수 |
| 필름스트립 | `ItemsView` + `LinedFlowLayout` 또는 `StackLayout(Horizontal)` | |
| 드래그앤드롭 | `CanDragItems` / `DragItemsStarting` + `AllowDrop` | 파일 드롭은 `DataPackageView.GetStorageItemsAsync` |
| 컨텍스트 메뉴 | `MenuFlyout` | |

**성능이 여기서 갈린다.** 수만 장 카탈로그에서 스크롤이 끊기면 제품이 못 쓰게 된다.
`ItemsView` 가상화 + 썸네일 디스크 캐시 + 비동기 디코드가 셋 다 필요하다.
→ [../14-persistence/catalog-and-storage.md](../14-persistence/catalog-and-storage.md)

### Canvas — 엔진이 직접 그린다

```
CanvasView                    메인 뷰            → SwapChainPanel
CanvasViewportState           줌·팬 상태          → 자체 (엔진 공유)
CanvasScrollPanBridge         스크롤 팬          → PointerWheelChanged + Manipulation
CanvasGeometry                좌표 변환          → 자체
CropOverlay                   크롭 오버레이       → XAML 오버레이 또는 D2D 직접
CanvasHUDLayer/ToolHUD        HUD               → XAML 오버레이 권장
CanvasCompareView/Divider     비교 분할          → 엔진 렌더
PixelSamplerReadoutView       픽셀 값 표시       → XAML
```

**분업 원칙: 픽셀은 D2D, 위젯은 XAML.**
크롭 핸들·HUD를 D2D로 그리면 히트 테스트·접근성·고DPI를 전부 손수 짜게 된다.
`SwapChainPanel` 위에 XAML 오버레이를 얹는 것이 정상 경로다.

⚠️ 단 **크롭 오버레이의 좌표계**는 엔진의 이미지 좌표와 일치해야 한다.
SwiftUI 판이 `CanvasGeometry`를 따로 둔 이유가 그것이다. 같은 변환 로직을
**엔진 쪽(C++)에 두고 Shell이 조회**하는 편이 두 벌 관리보다 안전하다.

### Develop — 인스펙터

```
BaseControlSection            기본 조정
ColorGradingSection           컬러 그레이딩
ColorMixerSection             컬러 믹서
BWToningSection               흑백 토닝
FilmEmulationSection          필름 에뮬레이션
ToneCurveEditor               톤커브 (+ PointEditing, PointFields)
Histogram/                    히스토그램
UserPresetSection             사용자 프리셋
DevelopQuickActionsSection    빠른 동작
LocalAdjustments/             국소 조정
Tools/                        도구
```

| SwiftUI | WinUI 3 |
|---|---|
| `Form(.grouped)` 섹션 | quiet native WinUI composition, Settings 화면은 Toolkit 후보 비교 |
| `InspectorSlider` + 편집 가능 값 | `Slider` + `NumberBox` 조합 |
| `ResettableSlider` | shared slider/value/reset composite control |
| 히스토그램 | 엔진이 준 빈 배열을 raw Direct2D 또는 경량 XAML geometry로 그림. Win2D는 기준 dependency가 아님 |
| 톤커브 에디터 | **커스텀 컨트롤 필수.** 기성품 없음 |

**⚠️ 슬라이더가 이 앱의 주 인터랙션이다.** macOS 판에는 다음이 다 들어 있다:

- 편집 가능한 숫자 텍스트(`EditableSliderValueText`)
- 포커스 이동(`InspectorSliderFocus`, `DevelopInspectorFocusNavigation`)
- 키보드 미세 조정(`DevelopKeyboardNudge`, `DevelopInspectorKeyboardController`)
- 개별 리셋(`DevelopInspectorResetter`)
- 값 포맷팅(`SliderValueFormatting`)

WinUI 3 기본 `Slider`로는 이 중 어느 것도 공짜가 아니다.
**슬라이더 복합 컨트롤을 하나 만들어 전 인스펙터가 재사용**하는 것이 유일하게 합리적인 경로다.
개별 화면마다 조합하면 7,997줄이 두 배가 된다.

또한 **드래그 중 조용한 빌드 + 제스처당 undo 한 번**이라는 규율이 macOS에 있다.
슬라이더를 움직일 때마다 undo가 쌓이면 못 쓴다. 커스텀 컨트롤에 이 동작을 넣는다.

### Defects — 난이도 최상

```
Brush/                        브러시 (ICEHealBrush 모델)
CloneStamp/                   복제 도장
RegionDefectOverlay           영역 지정
DefectMaskOverlay             마스크 오버레이
DefectLayerSection            레이어 목록
DefectEdit / DefectEditLabel  편집 기록 모델
Persistence/ Workflow/        세션 관리
AppModel+InfraredDefectRemoval  IR 결함 제거
```

**도구 역할 분담이 확정돼 있다(사용자 결정, 임의 변경 금지):**

| 도구 | 역할 |
|---|---|
| 자동 | 전역 기본 |
| 반자동(영역) | 먼지 |
| 브러시 | 미세 스크래치 + 잔여 |
| 복제 도장 | 임의 니즈 |

**필압/포인터 입력이 Windows에서 다르다.** `PointerPoint.Properties.Pressure`,
`PointerDeviceType`(Pen/Touch/Mouse)를 직접 다뤄야 한다. Wacom/Surface Pen 지원은
Windows Ink(`InkPresenter`)가 아니라 **원시 포인터 이벤트**로 가는 편이 제어가 낫다
(InkPresenter는 잉크 스트로크 모델이라 마스크 페인팅과 안 맞는다).

**⚠️ 이 기능은 성능 함정이 문서화돼 있다.** macOS에서 인터랙션 지연을 잡느라
캐시 계층을 여러 겹 만들었다(패치 캐시, 이전 베이스 캐시, 세션 원본 캐시, 단일 최종 flatten,
비동기 영속화). Windows에서 순진하게 만들면 같은 벽에 부딪힌다.
**처음부터 "레이어마다 전체 재합성" 구조를 피한다.**

### Export

```
ExportSection / ExportFormatOptionsView   포맷 옵션
ExportSettingsStore                       설정 저장
ExportArtifactCommitJournal (1,304줄)     산출물 커밋 저널
+ BatchExport, ExportNaming, ExportRecipe, ExportMetadata (Localization에서 확인)
```

`ExportArtifactCommitJournal`이 1,304줄인 것은 **중단·재개·부분 실패 처리**가 들어 있다는 뜻이다.
내보내기는 오래 걸리고 중간에 실패한다. Windows 판도 같은 저널 개념이 필요하다.

포맷 사양 → [../05-image-io/export-formats.md](../05-image-io/export-formats.md)

### Print

`PrintPackageInspectorControls` 791줄. 레이아웃 조판 + 인화 시뮬레이션이다. Windows 출력은
preview/page render와 OS print submission을 분리하고, `PrintManager`/`PrintDocument`·driver capability와
실물 인화 gate를 [Print surface 명세](surfaces/print.md)에서 확정한다. 이름만 보고 직접 XPS 경로를
기준선으로 정하지 않는다.

### Settings

```
AppSettingsView / AppSettingsTab          설정 창
ColorManagementSettingsSection            색 관리
DiskStorageSettingsSection                디스크 저장
MemoryCacheSettingsSection                메모리 캐시
ScanStorageLocationView                   스캔 저장 위치
LibraryBackupScheduleView / RestoreBrowser 백업·복원
ExternalBackupDestinationView             외부 백업
SupportBundleSettingsSection              지원 번들
LegalNoticeSettingsSection                법적 고지
```

`SettingsCard` / `SettingsExpander`는 유력한 후보지만 확정 dependency나 모든 행의 visual template가
아니다. macOS의 `Form(.grouped)` 규율은 quiet native hierarchy, 명확한 state, 전폭 입력과 불필요한
card/shadow 금지로 번역한다. Toolkit control은 실제 밀도·접근성·ARM64·servicing을 통과할 때 Settings의
적합한 행에만 쓰고, 실패하면 basic WinUI composition으로 같은 의미를 구현한다.

→ [settings-controls.md](settings-controls.md)

### Shortcuts

```
ShortcutRecorderField                     단축키 입력 필드
WorkflowShortcutsSettingsSection          워크플로 단축키
```

사용자 정의 단축키가 있다. WinUI 3에는 기성 "단축키 레코더"가 없다 —
`KeyboardAccelerator` + 커스텀 캡처 컨트롤을 만들어야 한다.

### Application lifecycle

현재 macOS판은 primary workspace, Settings, About, Help scene를 한 app process에서 소유하고 마지막 main
window close가 전체 종료를 요청한다. Windows App SDK WinUI 앱은 기본 multi-instance이므로 이를 그대로
두면 같은 catalog를 여는 두 shell이 생길 수 있다.

Windows 대응:

- user/channel/install identity별 primary UI process 하나
- custom `Main`에서 window·engine·catalog 생성 전 instance election
- second launch는 기존 process로 activation redirect
- main close는 verified catalog shutdown, auxiliary close는 해당 창만
- normal close와 logoff/restart/update/crash의 서로 다른 deadline
- x64·ARM64 동일 semantics

상세는 [앱 수명주기 명세](application-lifecycle.md)를 따른다.

## 재사용 가능한 자산 (재작성 아님)

| 자산 | 처리 |
|---|---|
| 다국어 문자열 6언어 | 문안 재사용 + `.resw` 변환 후보 + format/accessibility 재검증 |
| 단축키 정의 | 데이터로 이관 |
| 프리셋 JSON (6종) | 그대로 복사 |
| 스캐너 프로파일 JSON | 그대로 복사 |
| 기능 목록·화면 구성 | 이 문서 |

## 만들기 순서 제안

```text
M8   process lifecycle + Workspace shell + Canvas vertical slice
M9   Library + Import + catalog UX
M10  Develop inspector, shared slider control과 전체 adjustment surface
M11  Defects interaction, recipe와 cache
M12  Export, batch, naming, metadata와 commit journal
M13  Print preview/page/output
M14  Settings, shortcuts, localization와 accessibility
M15  Scanner host와 capability-driven UI
```

Localization resource pipeline과 shared control prototype은 M8부터 시작하지만, 각 surface의 문자열·focus·
accessibility acceptance가 끝나기 전 전체 이관 완료로 부르지 않는다. Defects는 어렵지만 Export 뒤로
미루지 않는다. canvas·engine·recipe/cache prerequisite가 갖춰진 M11에서 독립 gate로 닫는다.

## 관련

- [winui3.md](winui3.md) · [application-lifecycle.md](application-lifecycle.md) · [swapchainpanel-canvas.md](swapchainpanel-canvas.md) · [settings-controls.md](settings-controls.md)
- [../00-overview/architecture.md](../00-overview/architecture.md) — 경계 1(Shell↔Engine)
