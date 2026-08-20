# 셸·작업공간·내비게이션 명세

기준일: 2026-08-04  
macOS 근거: `ContentView*`, `Workspace*`, `WorkspaceToolbar*`, `WorkflowSidebar`

## 1. 제품 셸의 모양

Negaflow는 일반적인 문서형 `NavigationView` 앱이 아니다. 세 workspace가 같은 library selection과
frame을 공유하고 Develop/Print는 좌·중앙·우 panel과 filmstrip을 가진다.

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ Toolbar: scan/export | active-photo context | Library Develop Print | UI │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Library:  [source/organizer controls] | [grid / compare / survey]         │
│                                                                          │
│ Develop:  [workflow sidebar] | [canvas] | [develop inspector]             │
│                              | [filmstrip]                                │
│                              | [status]                                   │
│                                                                          │
│ Print:    [file/layout source] | [print canvas] | [print inspector]       │
│                              | [filmstrip]                                │
│                              | [status]                                   │
└──────────────────────────────────────────────────────────────────────────┘
```

catalog가 안전하게 열리지 않으면 이 구조 전체 대신 blocking recovery surface가 나온다. 빈
catalog로 조용히 진입하지 않는다.

## 2. WinUI 3 visual tree 제안

```text
Window
└── RootGrid
    ├── AppTitleBar / command strip
    ├── WorkspaceHost
    │   ├── LibraryWorkspace
    │   ├── DevelopWorkspace
    │   ├── PrintWorkspace
    │   └── CatalogRecoveryWorkspace
    ├── GlobalDragDropAdorner
    └── Modal/Flyout host
```

Develop/Print:

```text
Grid Columns="Auto, 1, *, 1, Auto"
├── LeftPanelHost
├── Divider/Splitter
├── CenterGrid Rows="*, Auto, Auto"
│   ├── CanvasHost
│   ├── FilmstripHost
│   └── StatusBar
├── Divider/Splitter
└── RightInspectorHost
```

panel은 overlay drawer가 아니라 중앙과 공간을 나누는 독립 column이다. 좁은 화면의 명시적
compact policy가 승인되기 전, inspector가 canvas 위에 겹치도록 자동 전환하지 않는다.

## 3. workspace navigation

순서:

```text
Library(0) → Develop(1) → Print(2)
```

entry point:

- toolbar text links
- View/menu command
- 사용자 지정 shortcut
- Library의 “Develop 열기” 행동
- 내부 workflow 요청

모든 entry가 하나의 `WorkspaceNavigationService.Select(module, reason)`로 모인다. XAML control이
각자 selection state를 직접 바꾸지 않는다.

전환 contract:

- 같은 module 선택은 no-op
- 방향은 navigation index로 계산
- Reduce Motion이면 이동 motion 제거
- Develop 진입 시 선택 frame의 rendering scope 동기화
- Library에서 Develop/Print로 넘어간 뒤 filmstrip scope를 다시 계산
- Develop/Print 진입 후 soft-proof preview가 필요하면 current revision으로 요청
- 전환 도중 새 전환이 오면 이전 completion task 취소
- focus는 workspace의 첫 의미 있는 target 또는 이전 workspace별 focus 기억으로 이동

## 4. startup·복구 순서

초기 화면을 먼저 `ready`로 그린 뒤 catalog 오류를 덮지 않는다.

```text
Window 생성
→ presentation preferences 읽기
→ catalog lifecycle: opening
→ schema/recovery/source state 검사
   ├─ blocked → CatalogRecoveryWorkspace
   └─ ready   → 저장된 module·frame 복구
→ active frame ID가 catalog에 있고 source available인지 검사
   ├─ 유효 → 선택
   └─ 무효 → 저장 ID 삭제, 최근 available frame 후보
→ filmstrip/query/render scope 동기화
```

Shell state와 catalog state를 같은 JSON blob에 묶지 않는다. shell preference가 손상돼도 catalog를
손상으로 판단하지 않고, catalog가 손상돼도 shell default로 빈 catalog를 덮어쓰지 않는다.

## 5. 저장되는 presentation 상태

현재 macOS 기준:

- workspace module, 기본 Develop
- Develop sidebar tab, 기본 Library
- Library search text, 최대 512자
- active frame ID
- left/right panel visibility
- filmstrip visibility
- left/right panel width를 각각 별도 저장
- Library view mode, sort key/order
- filmstrip sort key/order, scope, height, item scale
- Library folder expansion 상태
- selected settings tab

Windows key/schema는 새로 설계하되 stable action/surface ID를 사용한다.

규칙:

- UI thread slider tick마다 디스크 sync write 금지
- bounded debounce + app lifecycle flush
- versioned schema와 safe default
- 값 범위 clamp
- unknown enum은 default로 복구하고 진단
- panel width는 현재 window effective width에 다시 clamp
- 선택 ID는 실제 object/source validity 확인 후 적용
- search text는 normalization과 길이 제한

## 6. toolbar

현재 toolbar의 의미적 cluster:

```text
[Preview/Scan if capability] [Quick Export | Export]
                   [active frame RollToolbarStrip when width allows]
[Library | Develop | Print] [sidebar filmstrip inspector] [appearance] [utility]
```

### visibility와 enabled

- scanner가 없으면 scan cluster 자체가 없음
- scanner가 preview capability를 보고할 때만 Preview가 있음
- `canPreview`, `canScan`이 false면 button disabled
- scanning 중 compact progress indicator
- Quick Export/Export는 현재 workspace selection을 기준으로 각각 availability 계산
- active frame이 있고 toolbar 폭이 충분할 때만 중앙 photo controls
- module link는 selected state를 노출
- panel toggle은 on/off selected state를 노출
- utility에는 device detection, explicit simulator toggle, diagnostics

WinUI 구현은 `CommandBar`를 기계적으로 쓰기보다 현재 3-cluster 중심 정렬을 보존하는 custom Grid
안에 native `Button`, `ToggleButton`, `MenuFlyout`을 배치하는 편이 적합하다. primary command overflow가
생기면 우선순위는 문서로 고정한다.

### 좁은 창 우선순위

1. 현재 module과 workspace navigation
2. 현재 실행 가능한 Export/Scan의 primary command
3. panel visibility
4. 중앙 active-photo controls
5. appearance/diagnostics utility

숨겨진 command는 menu/shortcut에서 계속 접근 가능해야 한다. primary command가 말없이 사라지지
않고 overflow에 들어가며 automation name과 enabled state가 같다.

### title bar

- Windows system menu, minimize/maximize/close hit targets 보존
- draggable region과 button hit region이 겹치지 않음
- title bar double-click maximize/restore는 Windows 기본 동작에 맡김
- full screen과 maximized를 구분
- 고대비에서 custom title bar가 system caption보다 나빠지면 standard title bar로 후퇴
- RTL/localized title과 긴 text 검증

macOS traffic-light 여백 수치는 Windows로 옮기지 않는다.

## 7. 좌측 workflow sidebar

Develop tab:

| tab | 내용 | frame 없을 때 |
|---|---|---|
| Library | active frame folder를 포함한 library sources | source tree는 표시 가능 |
| Files | files source section | 표시 가능 |
| Versions | virtual copy, history, snapshot | 구체적 no-frame empty state |
| Presets | settings transfer, user preset | no-frame empty state |
| Film | film emulation | no-frame empty state |
| Output | Export section | no-export-frame empty state |

구조:

- 왼쪽 tab rail
- 선택 tab icon/title header
- 충분한 폭에서는 active frame display name/metadata summary
- Library/Files는 자체 scrolling behavior
- 나머지는 grouped form content
- tab은 selection semantics와 name을 UI Automation에 노출

현재 macOS에서 panel 폭 <300pt면 rail 76→48, header의 frame name이 숨는다. Windows에서도
effective width와 text scale을 함께 보고 compact mode를 결정한다. 임계값은 실측 후 정한다.

## 8. 우측 Develop inspector

- header: Develop label + scanner frame의 target/process 또는 imported photo EXIF 요약
- frame 있으면 `DevelopWorkflowInspector`
- frame 없으면 no-frame empty state
- vertical scroll
- compact width에서 horizontal padding 감소
- active tool은 crop/brush/region/clone/base-picker 중 하나만
- local adjustment와 위 도구도 mutual exclusion

inspector가 사라져도 current adjustment와 active tool이 임의로 reset되지 않는다. 그러나 사용자가
workspace를 바꾸거나 Escape를 누르는 제품 규칙에 따라 transient interaction은 정리될 수 있다.

## 9. panel resize

요구사항:

- left와 right width 독립
- drag 중 중앙 최소폭 보존
- pointer capture가 window 밖에서 끝나도 종료
- double-click reset 여부는 Windows convention/제품 결정 후 명시
- keyboard resize 대안 또는 splitter automation pattern
- 200% text에서 최소폭 재평가
- panel hidden→shown 시 마지막 유효폭 복구
- window 축소 시 stored 값 자체를 파괴하지 않고 effective width만 clamp
- window 확대 시 이전 사용자폭으로 복귀 가능

`GridSplitter` package를 채택할 경우 dependency와 accessibility를 검토한다. 간단한 native resize
thumb를 자체 구현할 때도 resize cursor, focus, keyboard, Automation RangeValue를 빠뜨리지 않는다.

## 10. 중앙 Develop surface

state:

| 조건 | 중앙 |
|---|---|
| actionable frame 있음 | color-managed Canvas |
| frame 없음, scanning 아님 | import/scan으로 이어지는 empty state |
| scanning 중, frame 없음 | canvas background + scan progress overlay |
| frame render pending | 이전 valid preview 또는 명시적 preparing state |
| source offline | available thumbnail + relink action, 작업별 disabled |
| engine/device recovery | recipe 보존 + recovery status |

Canvas XAML tree에는 native SwapChainPanel, crop/defect/local adjustment overlay, HUD와 accessible
controls가 들어간다. 픽셀 렌더와 UI overlay의 좌표 transform은 하나의 geometry snapshot을 공유한다.

## 11. filmstrip

Develop와 Print 중앙 하단에 동일한 filmstrip interaction을 쓴다.

- visible toggle
- height resize/저장
- item scale 감소·100% reset·증가
- sort key/order
- scope
- active/multi-selection
- previous/next photo command
- unavailable source 표시
- horizontal wheel/precision touchpad
- virtualization·async thumbnail

상태 bar 오른쪽의 scale/sort/scope controls가 filmstrip이 숨겨졌을 때 어떻게 동작할지 명시해야
한다. 기본은 filmstrip 표시 상태와 무관하게 preference 편집은 가능하되 불필요한 controls는
toolbar/menu로 이동하는 안을 실기 UX에서 비교한다.

## 12. status bar

현재 의미:

- leading: scan phase와 error log 연결 상태
- center/collapsible: Develop 처리 detail
- trailing: filmstrip size, sort, scope
- scan progress 막대와 퍼센트는 canvas overlay에 한 번만 표시

Windows판도 같은 진행률을 toolbar/status/canvas에 중복 표시하지 않는다.

진행 상태를 나눈다.

```text
queued
preparing first source
decoding/rendering/encoding
item N of M
committing/verifying
complete/cancelled/failed
```

0%에서 오래 도는 spinner 대신 아직 file preparation인지, 실제 pixel processing인지 구분한다.
screen reader에는 단계 전환과 terminal state를 live region으로 알리되 퍼센트 매 tick을 읽지 않는다.

## 13. Print workspace

Develop와 같은 panel visibility/width를 공유하지만 내용은 다르다.

- left: Print file/layout source tab
- center: active frame + actionable selected frames의 PrintCanvas
- bottom: 동일 filmstrip
- right: Print inspector
- no frame: printer icon empty state

multi-selection을 넓힐 때 active frame ID로 canvas 전체를 재생성해 방금 추가한 frame이 사라지는
구조를 피한다. print sheet identity와 active frame/selected frame collection을 분리한다.

## 14. Library workspace

Library는 Develop의 3-column을 재사용하지 않는다.

- resizable controls pane
- browser header/filter/search
- grid/compare/survey culling surface
- organizer/source tabs
- empty/recovery/duplicate/modal states

Library controls width range와 browser minimum width를 별도로 계산한다. Develop panel width를
Library에 단순 적용하지 않는다.

## 15. drag-and-drop import

root window는 external files의 drop target이다.

요구사항:

- supported item인지 drag-over에서 구분
- 전체 workspace 위에 방해되지 않는 drop adorner
- folder/file 혼합 처리 정책
- unsupported file의 부분 실패 보고
- shell item의 path/reparse/permission 검증
- duplicate/import transaction과 연결
- drop 중 workspace navigation·selection을 임의로 바꾸지 않음
- Narrator/keyboard 사용자를 위한 Import commands도 동일하게 제공

plugin executable이나 preset을 이미지 import drop으로 실행하지 않는다.

## 16. appearance

현재 `system`, `dark`, `light` 세 모드다.

- system theme 변경을 runtime에 반영
- canvas background preference와 app chrome theme 분리
- high contrast가 appearance override보다 우선
- image pixel에 UI theme transform을 적용하지 않음
- custom brush는 theme resource를 사용
- dark/light 전환 중 D2D display color transform이 불필요하게 재생성되지 않음

## 17. diagnostics utility

사용자 utility menu에서 scanner refresh, explicit simulator toggle, diagnostics report를 제공한다.

- simulator는 production scanner fallback이 아니라 명시적 mode
- diagnostics가 source path/image content/secret을 기본 수집하지 않음
- 장치 detection/scanning 중 refresh command disabled
- diagnostics popup/flyout은 keyboard focus와 close behavior 보유
- report generation은 UI thread를 막지 않음

## 18. focus 정책

- workspace 전환 전 module별 last focused surface를 기억할 수 있음
- 선택 frame이 바뀌어 inspector가 재생성돼도 focus를 무조건 root로 보내지 않음
- active tool 진입 시 canvas 또는 관련 first control로 focus
- panel hide 시 숨겨진 descendant focus를 toolbar toggle 또는 canvas로 이동
- modal close 시 invoking control로 복귀
- recovery surface에서 main workspace 뒤로 focus가 빠지지 않음
- title bar command와 content의 tab sequence가 예측 가능

## 19. shell automation ID 후보

macOS identifier 의미를 유지하되 Windows naming convention을 한 번 정한다.

| 의미 | AutomationId 후보 |
|---|---|
| root | `Negaflow.Main` |
| canvas | `Negaflow.Canvas` |
| Library/Develop/Print | `Negaflow.Workspace.Library` 등 |
| sidebar/filmstrip/inspector toggles | `Negaflow.Panel.*` |
| scan | `Negaflow.Scan` |
| Quick Export/Export | `Negaflow.QuickExport`, `Negaflow.Export` |
| filmstrip scope | `Negaflow.Filmstrip.Scope` |

AutomationId는 localization하지 않는다. visible/accessibility name은 localization한다.

## 20. acceptance scenarios

- 저장 상태 없는 첫 실행은 Develop, Library sidebar, 양쪽 panel/filmstrip visible로 일관되게 시작
- 마지막 module·panel·filmstrip/search/active frame 복구
- source offline이면 stale active frame 복구하지 않음
- catalog blocked이면 어떤 module도 뒤에 interactive하지 않음
- Library→Develop→Print 연속 전환 중 stale delayed completion 없음
- Reduce Motion에서 directional movement 없음
- 좌우 splitter를 각각 움직여도 반대 폭 불변
- narrow/200% text에서 명령 접근 가능
- panel toggle의 selected/pressed/automation state 정확
- scan capability가 preview를 보고하지 않으면 Preview command가 없음
- Quick Export/Export의 toolbar/menu/shortcut enabled 상태 일치
- scan progress가 한 위치에만 명확히 나타남
- window drag/drop import가 transaction/error UI로 연결
- high contrast/full screen/multi-monitor에서 title bar hit target 정상

