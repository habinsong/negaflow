# 입력·명령·사용자 지정 단축키 명세

기준일: 2026-08-04  
macOS 기준: 7개 command group, 66개 stable action ID

## 1. 명령이 UI보다 먼저다

toolbar, menu, context menu, button, shortcut가 서로 다른 코드를 실행하지 않는다.

```text
CommandRegistry
├── action ID
├── localized title/description
├── canExecute(current context)
├── execute(current context)
├── current/default shortcut
└── telemetry-free local diagnostics
```

WinUI `ICommand` 또는 별도 command service가 유일한 enabled/execute truth다. button만 disabled이고
shortcut은 실행되거나, menu와 toolbar selection 대상이 다른 상태를 금지한다.

## 2. action inventory

### Library

`importImages`, `importFolder`, `refreshLibrary`, `loadScanner`, `libraryGrid`, `libraryCompare`,
`librarySurvey`

### Photo

`previousPhoto`, `nextPhoto`, `pickPhoto`, `clearPick`, `rejectPhoto`, `deletePhoto`, `rateZero`,
`rateOne`, `rateTwo`, `rateThree`, `rateFour`, `rateFive`, `createVirtualCopy`

### Develop

`autoTone`, `autoWhiteBalance`, `toggleAutoColor`, `toggleAutoLevels`, `toggleNoiseReduction`,
`resetAdjustments`, `copyDevelopSettings`, `pasteDevelopSettings`, `processColorNegative`,
`processColorPositive`, `processBWNegative`, `processBWPositive`, `targetMain`, `targetPrint`,
`targetHS`, `targetSP`, `targetF135`, `targetHR`, `targetExpired`, `cropTool`, `basePickerTool`,
`autoDefectTool`, `guidedDefectTool`, `brushDefectTool`, `cloneStampTool`, `rotateLeft`,
`rotateRight`, `flipHorizontal`, `flipVertical`, `toggleBeforeAfter`

### View

`showHideSidebar`, `showHideFilmstrip`, `showHideInspector`, `toggleFullScreen`,
`openLibraryWorkspace`, `openDevelopWorkspace`, `openPrintWorkspace`

### Scanner

`detectScanners`, `toggleScannerSimulator`, `previewScan`, `scanFrame`, `addFlatbedFrame`,
`removeFlatbedFrame`

### Export

`quickExport`, `exportPhoto`

### Help

`openHelp`

action ID는 localization하거나 Windows class 이름으로 바꾸지 않는다. macOS와 Windows의 기본
key가 달라도 동일한 제품 의미를 추적한다.

## 3. 현재 enabled contract

### 항상 가능한 명령

앱 lifecycle이 blocking recovery가 아닌 일반 상태라는 전제에서:

- import, folder import, refresh, scanner setup
- Library grid/compare/survey 전환
- panel·filmstrip·inspector visibility
- full screen과 workspace navigation
- development process와 target 선택
- explicit scanner simulator toggle
- help

process/target action이 frame 없이도 “항상 true”인 현재 macOS 구현은 실행 함수에서 no-op이 될 수
있다. Windows UX에서는 menu가 enabled인데 아무 일도 없는 상태가 바람직한지 기준 앱을 실제
확인한 뒤, 제품 사양을 `frame 필요`로 정정할지 delta register에 올린다. 코드 한 줄만 보고
의도라고 단정하지 않는다.

### frame이 필요한 명령

- pick/clear/reject/delete/rating/virtual copy
- auto tone/WB/noise, reset, copy
- crop/defect tools, rotate/flip, before/after

### 추가 조건

| action | 조건 |
|---|---|
| previous/next | interaction scope에서 앞/뒤 frame 존재 |
| auto color/auto levels/base picker | inversion이 필요한 film type |
| paste settings | frame + copied settings |
| detect scanner | detecting/scanning 아님 |
| preview scan | plugin capability와 current state의 `canPreview` |
| scan frame | `canScan` |
| add flatbed frame | flatbed region workflow + preview + scanning 아님 |
| remove flatbed frame | selected region + scanning 아님 |
| Quick Export | active workspace selection에 대한 availability |
| Export | active workspace selection에 대한 availability |

catalog blocking recovery, modal transaction, engine shutdown 같은 Windows-specific global gate는
command service 맨 앞에서 적용한다.

## 4. command context

single-key 사진 명령은 text 입력 중 실행되면 안 된다.

context priority:

```text
modal dialog / shortcut recorder
→ text editing / IME composition / NumberBox editing
→ active Canvas tool
→ focused Library/Filmstrip selection
→ workspace global
→ app global
```

예:

- search box에서 `P`는 글자 입력이지 Pick이 아니다.
- NumberBox에서 `1`은 rating 1이 아니다.
- tone curve point field의 Delete는 사진 삭제가 아니다.
- shortcut recorder에서 Escape는 recorder cancel이며 active crop cancel까지 전달하지 않는다.
- Canvas가 active tool을 소유할 때 bracket가 brush size인지 previous photo인지 명시한다.

`handled` 여부와 command routing을 한 서비스에서 관리한다. 여러 XAML ancestor가 같은 key를
중복 실행하지 않게 한다.

## 5. Windows 기본 shortcut 설계 원칙

macOS key chord의 `Command→Ctrl`, `Option→Alt` 일괄 치환은 금지한다.

이유:

- `Ctrl+Alt`는 많은 국제 키보드에서 AltGr와 같은 입력으로 보고될 수 있다.
- Alt는 menu access와 충돌한다.
- Windows에는 F1/F5/F11 등 강한 관습이 있다.
- Ctrl+C/V는 text editing과 scope 충돌이 있다.
- OEM punctuation key는 keyboard layout마다 character가 다르다.
- Delete와 Backspace가 macOS naming과 다르다.

우선순위:

1. Windows convention: Help F1, Refresh F5, Full screen F11 후보
2. 사진 앱의 modifier 없는 culling/rating/tool muscle memory
3. 기존 Negaflow의 의미적 grouping
4. 6개 지원 언어 keyboard layout에서 충돌 없음
5. menu에서 현재 binding 표시

## 6. 초기 Windows mapping 후보

아래는 구현 전 keyboard-layout QA 후보이며 확정값이 아니다.

| action | 후보 | 비고 |
|---|---|---|
| import images | `Ctrl+I` | 일반 명령 |
| import folder | `Ctrl+Shift+I` | |
| refresh library | `F5` | Windows 관습. `Ctrl+R` 후보와 비교 |
| grid/compare/survey | `G` / `C` / `N` | text edit가 아닐 때만 |
| previous/next | `[` / `]` 또는 Left/Right | keyboard layout·canvas pan 충돌 검증 |
| pick/clear/reject | `P` / `U` / `X` | 사진 앱 muscle memory |
| rating | `0`…`5` | main row+numpad 정책 명시 |
| delete photo | `Delete` | text/curve/list context 보호 |
| auto tone | `Ctrl+U` | current muscle memory 후보 |
| auto WB | `Ctrl+Shift+U` | |
| copy/paste develop | `Ctrl+Shift+C/V` | 일반 clipboard와 구분 |
| crop/base picker | `R` / `W` | context only |
| auto/guided/brush/clone | `Shift+Q` / `Q` / `B` / `S` | context only |
| before/after | `\` | keyboard layout 검증 |
| full screen | `F11` | Windows 관습 |
| quick export | `Ctrl+E` | |
| export dialog | `Ctrl+Shift+E` | |
| help | `F1` | Windows 관습 |

다음 군은 숫자와 modifier 충돌이 많아 별도 사용성 시험 후 확정한다.

- process 4종
- target 7종
- panel 3종
- workspace 3종
- scanner 6종
- rotate/flip

모든 action은 menu와 Settings recorder로 접근 가능해야 하며, 출시 전에는 66개 action 모두 기본
binding 또는 의도적인 `unassigned` 결정과 이유를 가져야 한다. macOS에 shortcut이 있는데
Windows에서 누락된 채 넘어가면 parity gap이다.

## 7. key identity와 저장 형식

저장할 것은 표시 문자열이 아니라 canonical key다.

```text
schema_version
action_id
virtual_key_or_oem_key
modifiers: ctrl/shift/alt
keypad distinction policy
layout_independent flag if applicable
```

규칙:

- Win key는 사용자 shortcut modifier로 허용하지 않는다.
- OS가 예약한 chord는 거부한다.
- letter/digit/function/arrow/navigation/OEM punctuation을 명시적 enum으로 제한한다.
- 표시 문자열은 현재 keyboard layout과 locale로 생성한다.
- 저장 파일에서 localized `Ctrl`, `Umschalt` 같은 텍스트를 파싱하지 않는다.
- key layout 변경 뒤 binding의 실제 의미와 표시를 일관되게 처리한다.
- schema migration이 실패하면 전체 설정을 버리지 않고 잘못된 action만 default로 복구한다.

물리 key 위치와 논리 character 중 무엇을 보존할지는 culling tool과 menu accelerator에서 다를 수
있다. 첫 keyboard spike에서 US, Korean, German, French AZERTY를 비교해 한 정책을 확정한다.

## 8. AltGr와 IME

필수 규칙:

- 오른쪽 Alt/AltGr text composition을 `Ctrl+Alt` shortcut으로 오인하지 않는다.
- IME composition 중 modifier 없는 workflow action을 실행하지 않는다.
- 한글 조합 중 key-up에서 action이 뒤늦게 실행되지 않는다.
- dead key 뒤의 OEM punctuation을 recorder가 잘못 확정하지 않는다.
- shortcut recorder는 현재 조합을 취소·확정하는 IME event와 command Escape를 분리한다.

테스트 layout:

- English US
- Korean 2-set + English 전환
- Japanese IME
- Simplified Chinese Pinyin
- German QWERTZ/AltGr
- French AZERTY

지원 UI 언어와 keyboard layout은 같을 필요가 없으므로 교차 조합도 시험한다.

## 9. shortcut recorder

현재 macOS 동작을 Windows 네이티브로 번역한다.

### 상태

```text
idle: current chord 표시
→ recording: prompt + 현재 modifier/key preview
   ├─ valid key-up → conflict/validity 검사 → commit
   ├─ Escape → cancel, 기존 값 유지
   ├─ invalid/reserved → error, 기존 값 유지
   └─ focus/window lost → cancel
```

### UI

- keyboard focus 가능한 bordered control
- click/Enter/Space로 recording 시작
- monospace일 필요는 없지만 keycap/chord가 안정적으로 정렬
- recording 상태를 spinner보다 text/state로 명확히 표시
- action별 reset button
- reset all
- invalid/conflict help text가 바로 아래 표시
- screen reader에 현재 chord, recording, accepted/rejected 이유 알림

### validation

- key 하나 + 허용 modifier
- modifier만으로 commit 금지
- duplicate action conflict 금지 — macOS 현재 정책 유지
- OS reserved 및 Win modifier 금지
- text composition용 AltGr chord 거부/경고
- Escape는 binding으로 기록하지 않고 cancel
- empty/unrecognized key 거부

conflict 오류는 “유효하지 않음” 하나로 뭉치지 않고 어떤 action이 이미 사용 중인지 표시하는 것이
Windows UX 개선 후보다. 기능 의미를 바꾸지 않는 설명 개선으로 delta에 기록한다.

## 10. 메뉴와 표시

- main menu/CommandBar flyout이 current user override를 즉시 표시
- shortcut reset 뒤 모든 entry가 같은 default 표시
- disabled command도 shortcut hint는 보일 수 있으나 이유를 설명
- icon-only toolbar는 tooltip에 command name + shortcut
- localization과 key display를 이어 붙인 hard-coded 문자열 금지
- shortcut text가 길어져도 menu label을 밀어내지 않음

WinUI `KeyboardAcceleratorTextOverride` 같은 표시 기능을 쓰더라도 command registry의 canonical
display가 truth다.

## 11. 도구 입력과 Escape

Develop에서 다음은 mutual exclusive다.

- crop
- base picker
- auto/guided region defect
- brush defect
- clone stamp
- local adjustment

새 도구 진입:

1. current transient interaction 종료
2. region detection session이 있으면 cancel/cleanup
3. 새 tool을 current frame revision에 귀속
4. 필요한 canvas focus/cursor/overlay 설정

같은 shortcut을 다시 누르면 tool을 끈다. Escape는 가장 안쪽 interaction부터 닫고 처리된 경우
workspace/global까지 전파하지 않는다.

권장 Escape 우선순위:

```text
open menu/flyout/dialog
→ shortcut recording/inline value edit
→ active stroke/clone source/region gesture
→ active Develop tool/local adjustment
→ temporary before-after/overlay
→ no-op
```

## 12. pointer·wheel·touchpad

### Canvas

- primary drag: active tool 또는 pan policy
- space+drag pan 후보는 text focus와 구분
- wheel: zoom 또는 scroll policy를 명시, modifier 조합 포함
- precision touchpad pinch: zoom around pointer/focal point
- double click: fit/100% 같은 제품 결정
- pointer capture와 cancel/lost capture
- high-frequency move는 coalesce하고 render request를 bounded

### Filmstrip/Library

- click, Ctrl-click, Shift range, right-click selection semantics
- horizontal wheel bridge
- drag reorder/stack/import가 selection과 충돌하지 않음
- context menu를 연다고 selection을 잘못 바꾸지 않음
- touch long-press는 필수 기능이 아니라 후보

## 13. pen과 Defects

- pointer device type: mouse/pen/touch 구분
- pressure가 없으면 stable default 1.0
- pressure range clamp와 NaN 거부
- eraser/barrel button 지원은 명시적 tool mapping
- tilt는 제품에서 쓰지 않으면 수집·저장하지 않음
- stroke points를 image coordinate와 timestamp/pressure로 snapshot
- display DPI나 zoom이 recipe geometry를 바꾸지 않음
- pointer lost/cancel 시 incomplete stroke rollback
- Wacom/Surface Pen 실기 QA

Windows Ink의 stroke object를 제품 recipe truth로 삼지 않는다. Negaflow의 brush/clone semantics와
coordinate/revision contract가 truth다.

## 14. undo/redo

input event마다 undo를 만들지 않는다.

- slider drag: gesture 시작 전 값 → 연속 preview → pointer/key commit에서 undo 1개
- keyboard nudge: 반복 key-down을 time/gesture boundary로 묶는 정책
- brush stroke: 한 stroke가 한 undo
- crop drag: 한 drag가 한 undo
- batch paste/reset: 사용자 action 단위
- cancelled gesture: undo entry 없음
- stale render completion: undo와 무관

Ctrl+Z/Y 또는 Ctrl+Shift+Z의 Windows default는 app 전체 undo manager와 text field local undo를
context에 따라 구분한다.

## 15. accessibility input

- 모든 pointer-only tool에 keyboard entry와 종료 제공
- crop/curve point는 keyboard nudge와 값 편집 대안
- splitter keyboard resize
- toolbar selected toggle state
- shortcut recorder가 screen reader focus를 가두지 않음
- key repeat가 지나치게 빠른 destructive action을 반복하지 않음
- Delete photo는 confirmation/undo 제품 계약과 연결

## 16. 테스트

### command consistency

- 66 action ID 모두 registry, title, group, execute, enabled rule 보유
- toolbar/menu/context/shortcut가 같은 command instance 또는 같은 truth 사용
- frame/selection/scanner/export 상태 변화 때 enabled 동기화
- disabled shortcut은 실행도 side effect도 없음

### recorder

- commit/cancel/invalid/conflict/reset/reset-all
- focus loss/window close
- modifier-only, key repeat, key-up ordering
- AltGr, IME, dead keys, OEM punctuation, numpad
- persistence/restart/schema migration
- accessible announcements

### context

- SearchBox/NumberBox/ToneCurve text edit 중 single-key action 억제
- modal dialog 뒤 global action 억제
- Canvas/Library/Filmstrip focus별 previous/next/delete
- active tool Escape ordering
- held key가 workspace 전환 뒤 다른 action으로 이어지지 않음

## 17. 출시 전 미결정

- 66개 action의 Windows default chord 최종표
- logical character 대 physical key 정책
- numpad rating 지원
- global shortcut 범위와 multi-window 정책
- panel/workspace/process/target 숫자 chord
- WinUI `KeyboardAccelerator`만으로 충분한지, custom routed input가 필요한지
- shortcut import/export 기능이 필요한지

이 항목은 구현자가 임의로 결정하지 않고 US/Korean/German/French keyboard 실기와 macOS 사용자
muscle-memory 비교를 포함한 keyboard spike에서 승인한다.

## 공식 참고

- [Keyboard accelerators](https://learn.microsoft.com/en-us/windows/apps/design/input/keyboard-accelerators)
- [Keyboard interactions](https://learn.microsoft.com/en-us/windows/apps/design/input/keyboard-interactions)
- [Pointer input](https://learn.microsoft.com/en-us/windows/apps/design/input/handle-pointer-input)
- [Pen interactions and Windows Ink](https://learn.microsoft.com/en-us/windows/apps/design/input/pen-and-stylus-interactions)

