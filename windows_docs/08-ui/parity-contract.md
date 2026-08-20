# WinUI 3 UI/UX 동등성 계약

기준일: 2026-08-04  
macOS 기준 커밋: `9be909c` + 명시적으로 승인된 후속 delta만  
목표: 현재 macOS Negaflow와 제품 경험 99.9% 동등

## 1. 99.9%의 의미

99.9%는 macOS screenshot을 Windows에 픽셀 복사한다는 뜻이 아니다. 다음 네 가지가 거의 완전히
같다는 제품 목표다.

1. 사용자가 할 수 있는 작업과 할 수 없는 조건
2. 작업 전후의 상태, 결과와 persistence
3. 오류·취소·복구·재시작 경로
4. 정보 위계, 밀도, 직접 조작과 피드백의 품질

Windows는 Windows답게 보여야 한다. title bar, system menu, modifier key, file picker, focus visual,
scrollbar, context menu, typography, high contrast는 WinUI 3와 Windows 규칙을 따른다. 이러한
플랫폼 번역은 parity gap이 아니다. 반대로 모양이 비슷해도 결과, disabled 조건, 선택 복구 또는
단축키 흐름이 다르면 parity 실패다.

`99.9%`를 임의 점수 하나로 계산하지 않는다. 출시 게이트는 다음처럼 객관화한다.

- 모든 기준 surface와 state가 manifest에 있음
- P0/P1 기능·데이터·복구 delta 0개
- 접근성 blocker 0개
- 미해결 visual delta는 명시된 플랫폼 번역 또는 승인된 작은 P2만
- cross-surface workflow golden 전부 통과
- 실제 Windows와 macOS 비교 QA artifact 존재

## 2. 기준선이 움직이지 않게 한다

각 Windows milestone은 `MacBaselineManifest`를 가진다.

```text
mac_commit
working_tree_policy
app_source_inventory_hash
localization_manifest_hash
shortcut_manifest_hash
accessibility_id_manifest_hash
pipeline_asset_hashes
surface_spec_version
capture_environment
known_deltas
```

실제 artifact set, stable ID, generated/curated provenance, semantic diff와 evidence index는
[기준선 manifest 명세](../99-plan/baseline-manifest.md)가 소유한다. 정규식 count나 screenshot hash만으로
manifest를 대체하지 않는다.

현재 워킹트리의 미커밋 코드는 관찰 자료일 뿐 자동 baseline이 아니다. 예를 들어 2026-08-04
현재 Metal kernel 추가 작업이 보이더라도 커밋·승인 전에는 Windows 기능 요구로 확정하지 않는다.

macOS main이 바뀌면 Windows 작업을 무조건 중단하지 않는다. delta triage에서 다음으로 분류한다.

| 분류 | 처리 |
|---|---|
| 버그 수정·데이터 안전 | 현재 milestone에 backport 검토 |
| 사용자 노출 기능 | 다음 parity batch 또는 현재 범위 승인 |
| macOS 전용 chrome | Windows delta 없음 |
| 실험·미커밋 | 사양에 포함하지 않음 |
| 제거/rename | localization·shortcut·automation ID migration 포함 |

## 3. 현재 최상위 제품 구조

소스 기준 최상위 workspace module은 세 개다.

```text
Library  →  Develop  →  Print
```

공통 shell:

- 상단 `WorkspaceToolbar`
- module content
- Develop/Print의 좌측 패널, 중앙 surface, 우측 inspector
- Develop의 하단 filmstrip
- catalog blocked 시 workspace 전체를 대체하는 recovery surface
- drag-and-drop import target
- scan/develop/export/print 진행·상태 피드백
- menu와 사용자 지정 workflow shortcuts
- main window close 시 전체 app 종료, auxiliary window close 시 해당 창만 종료
- second launch가 새 model/catalog writer를 만들지 않고 기존 process를 활성화

WinUI판은 top-level `NavigationView`가 이 제품 구조를 자동으로 해결한다고 가정하지 않는다. 현재
macOS판도 겹침을 피하려고 명시적 3-column layout을 쓴다. Windows에서도 `Grid`, column/row
splitter, persistent widths와 중앙 최소폭을 직접 소유하는 것이 기본안이다.

## 4. 현재 shell 수치와 동작 기준

소스에서 관찰된 값:

| 항목 | macOS 기준 | Windows 번역 |
|---|---|---|
| regular width threshold | 1,340pt | effective pixels 기준 초기값, DPI별 실측 |
| Develop panel default | 430pt | 430 effective px 후보 |
| panel regular min/max | 300/560pt | 중앙 최소폭과 함께 clamp |
| compact panel min | 220pt | control truncation 검증 후 확정 |
| Develop center min | 480 regular, 400 compact | canvas 기능 보존 |
| Library browser min | 560 regular, 420 compact | grid virtualization 유지 |
| toolbar height | 40pt | native title bar 통합 여부와 함께 측정 |
| status bar height | 30pt | 표시 정보와 접근성 유지 |
| module transition | 140ms snappy | Windows motion curve로 번역, Reduce Motion 시 제거 |
| filmstrip | visible/height/item scale/sort/scope 저장 | 동일 상태 복구 |

숫자를 무조건 1:1 복사하지 않는다. macOS point와 Windows effective pixel의 실제 글꼴·control
metric이 다르므로 다음을 함께 만족하는 가장 가까운 값을 확정한다.

- 같은 정보 밀도
- slider·label이 잘리지 않음
- 중앙 이미지가 실질적으로 사용 가능
- panel resize가 반대편 값을 바꾸지 않음
- 100/125/150/200% DPI와 text scale
- 최소 창 크기에서 명령 유실 없음

## 5. surface manifest

각 surface는 stable ID와 다음 항목을 갖는다.

```text
surface_id
mac_source_files
entry_conditions
exit_conditions
visual_hierarchy
commands_and_disabled_rules
states
focus_order
keyboard_and_pointer
accessibility_contract
localization_keys
persistent_state
engine_requests_and_events
performance_budget
mac_reference_artifacts
windows_reference_artifacts
known_platform_translations
test_ids
```

stable ID 예:

```text
shell.main
shell.toolbar
library.grid
library.compare
library.survey
develop.canvas
develop.inspector.base
develop.inspector.curve
defects.brush
export.dialog
print.contact-sheet
scan.preview
settings.color-management
recovery.catalog-blocked
```

XAML class 이름을 surface ID로 쓰지 않는다. 리팩터링돼도 제품 기능 ID는 유지한다.

## 6. state inventory

모든 surface는 해당되는 상태를 명시한다.

| 상태 | 확인할 것 |
|---|---|
| initial | 저장 상태가 적용되기 전 skeleton/blank flicker |
| loading | 진행 원인과 취소 가능 여부 |
| empty | 첫 행동으로 이어지는 구체적 안내 |
| ready | 정상 명령·selection·focus |
| disabled | 이유, tooltip/help, shortcut도 같은 규칙 |
| busy foreground | 중복 실행 차단, UI 피드백 |
| busy background | 편집 가능 범위와 우선순위 |
| partial success | 완료 항목과 실패 항목 구분 |
| error recoverable | retry/relink/settings/space 확보 |
| error blocking | catalog recovery처럼 workspace 대체 |
| cancelled | 데이터 rollback과 progress 정리 |
| stale | selection/revision 변경 뒤 결과 무시 |
| offline source | thumbnail/metadata와 원본 필요 동작 구분 |
| permission/trust | scanner plugin·folder access 안내 |

happy path screenshot만 있으면 surface spec가 아니다.

## 7. 동등성 축

### 기능

- command 존재
- entry point 존재: toolbar/menu/context/shortcut
- 활성·비활성 조건 동일
- 결과와 undo/redo 동일
- batch와 multi-selection semantics 동일
- import/remove/delete/relink 차이 보존

### 정보 구조

- 주요 작업이 같은 module 안에 있음
- 좌측 source/organizer, 중앙 content, 우측 inspector의 역할 유지
- 자주 쓰는 명령과 고급 설정의 위계 유지
- 상태·오류가 관련 surface 근처에 표시
- panel, section, tab의 collapse/selection 저장

### 시각

- quiet native controls, 불필요한 card/gradient/shadow 없음
- 같은 상대적 밀도와 강조
- image가 주인공이고 chrome이 과도하게 넓지 않음
- hover/pressed/selected/focus/disabled가 구분됨
- icon만 있는 버튼은 tooltip과 automation name 보유
- loading ring이 결과 없이 0%에 오래 머물지 않음

### 입력

- keyboard-only 전체 workflow
- mouse, precision touchpad, wheel, drag/drop
- pen pressure가 필요한 Defects 경로
- Escape가 active tool/interaction을 취소하는 순서
- focus가 dialog/section 전환 뒤 사라지지 않음
- Windows modifier와 system reserved chord 충돌 없음

### 데이터와 persistence

- workspace/module, panel visibility/width, filmstrip state 복구
- selected frame은 존재하고 source available일 때만 복구
- folder expansion state 보존
- Develop/Defect recipe와 undo boundary
- export/print/scanner job checkpoint
- corrupt/missing state는 빈 catalog로 오인하지 않음

### 앱 수명주기

- cold launch와 warm activation의 state 적용 순서가 구분됨
- 사용자·제품 채널별 primary UI process 하나
- second launch/activation이 current destructive transaction을 침범하지 않음
- main close는 최신 catalog generation read-back과 승인된 backup 정책을 통과
- normal close, installer close, logoff/restart, crash/power-loss를 같은 save 기회로 간주하지 않음
- x64와 ARM64가 같은 instance election·activation·shutdown semantics를 가짐

### 접근성

- automation name, role/control type, value, state
- selection와 multi-selection
- live progress/error announcements
- focus order와 keyboard trap 없음
- high contrast, text scale, Reduce Motion
- color만으로 rating/pick/reject/status를 전달하지 않음

### 성능

- 입력 후 visual response latency
- scroll frame pacing과 virtualization
- slider drag의 submit/preview cadence
- selection 변경 뒤 stale preview 방지
- 첫 파일 준비와 progress 표시 분리
- background work가 foreground interaction을 막지 않음

## 8. 플랫폼 번역 규칙

| macOS | Windows |
|---|---|
| Command | Ctrl이 일반적인 명령은 Ctrl, Windows 관습과 충돌 시 별도 매핑 |
| Option | Alt 또는 보조 modifier, 메뉴 활성과 충돌 검증 |
| Control | Ctrl을 이미 쓰는 경우 action 의미별 재설계 |
| traffic-light title bar | Windows AppWindow/title bar/system menu |
| sheet | ContentDialog, modal window 또는 in-page surface |
| NSOpenPanel/NSSavePanel | Windows file/folder picker 또는 Win32 dialog |
| Finder reveal | Explorer에서 선택 표시 |
| help tag | ToolTip + accessible description |
| SF Symbols | Segoe Fluent Icons 또는 제품 vector asset |
| system Form | WinUI native layout/Toolkit control 후보 |
| accessibility identifier | AutomationId |

단축키는 기계적 문자 치환을 하지 않는다. macOS에서 `Command+Option+1`이더라도 Windows에서
`Ctrl+Alt+1`이 OS/입력기와 충돌하면 제품 action ID는 유지하고 chord를 다시 정한다.

## 9. 모션

현재 module 전환은 방향성과 140ms opacity/move를 사용하고 Reduce Motion이면 opacity 또는
animation 제거로 바뀐다.

Windows 원칙:

- system animation setting 존중
- 업무 흐름을 늦추는 decorative motion 금지
- module 방향은 Library→Develop→Print의 navigation order와 일치
- selection/slider/thumbnail에서 과도한 spring 금지
- device-lost/recovery 중 무한 spinner 금지
- 화면 전환 후 focus target이 예측 가능

macOS curve를 직접 복제하기보다 Windows Composition/WinUI의 native motion 안에서 같은 의미와
속도를 만든다.

## 10. 반응형·DPI·창 상태

필수 matrix:

- 1280×720 상당 최소 후보
- 1440×900, 1920×1080, 2560×1440, 4K
- 100%, 125%, 150%, 175%, 200% DPI
- Windows text size 100~200%
- maximized, restored, full screen
- 좌/우 panel 각각 on/off, filmstrip on/off
- 창을 서로 다른 DPI/ICC 모니터 사이로 이동
- 좁은 창에서 toolbar 명령 보존

좁은 화면에서 command를 임의로 wrap해 두 줄로 만들지 않는다. 현재 macOS toolbar의 center
photo control은 폭 조건에 따라 숨김/대체되는 로직이 있다. Windows판도 command priority,
overflow menu, horizontal scroll 중 제품에 맞는 명시적 정책을 surface별로 정한다.

## 11. 기준 artifact

macOS에서 각 surface마다 수집:

- 스크린샷: light/dark, empty/ready/error/disabled, 핵심 locale
- 짧은 입력 capture: pointer, keyboard, transition, resize
- accessibility tree 또는 identifier/name/state dump
- menu와 shortcut manifest
- AppStorage/persistence key와 restore scenario
- source file 목록과 commit
- 실제 loaded photo와 synthetic fixture

Windows에서 같은 시나리오를 수집하고 side-by-side review한다. screenshot diff는 layout drift를
찾는 보조 수단이다. font rasterization, native chrome, focus visual 때문에 pixel-diff threshold만으로
합격시키지 않는다.

## 12. 우선순위

| 등급 | 예 | 출시 처리 |
|---|---|---|
| P0 | 원본 삭제 혼동, 잘못된 frame에 결과 적용, export 품질 오류 | 반드시 0 |
| P1 | 기능 누락, disabled 규칙, recovery/keyboard/accessibility blocker | 반드시 0 |
| P2 | spacing, native icon 차이, 작은 motion 차이 | 플랫폼 번역 또는 명시 승인 |
| P3 | 내부 class/파일 구조 차이 | parity 범위 아님 |

99.9%를 이유로 P0/P1 하나를 “0.1%”로 미루지 않는다.

## 13. cross-surface golden workflow

### Import → Library → Develop → Export

1. 파일/폴더 import
2. thumbnail·source availability 표시
3. grid/compare/survey selection
4. Develop 진입과 active frame 복구
5. process/target 선택, 수동 조정, before/after
6. Defect recipe 편집
7. ordinary Export와 Quick Export
8. 산출물 reveal, restart 뒤 상태 복구

### Scan → Develop → Export

1. plugin detection/trust
2. capability load
3. preview 가능할 때만 preview UI
4. frame/ROI 설정
5. scan 진행·취소·manifest
6. library publication
7. Develop과 export

### Library maintenance

1. source offline
2. relink/move
3. remove from library와 source trash의 구분
4. backup/restore
5. catalog corrupt/blocking recovery

### Restart·activation·close

1. cold launch와 catalog restore
2. second launch가 기존 main으로 전달
3. dirty generation 중 main close
4. commit 중 더 최신 generation 생성
5. read-back 또는 backup 실패
6. logoff/update close와 다음 launch recovery
7. Stable/Beta side-by-side와 같은 library lock 충돌

### Print

1. selection과 filmstrip scope
2. single/contact-sheet layout
3. page/printer/profile 설정
4. preview
5. print 또는 print-package export
6. 실패·취소·재시도

## 14. UI test의 역할

자동화:

- AutomationId와 semantic query
- 핵심 command의 enabled state
- navigation, dialog, focus, persistence
- resize/DPI 일부 matrix
- localization missing/truncation heuristic
- accessibility scanner

수동:

- 이미지 중심 위계와 실제 사용감
- pen/touchpad, high-DPI/multi-monitor
- Narrator workflow
- 긴 session과 thermal/performance
- print/scanner 실장치
- subtle color/overlay/focus visual

자동화 통과를 click-through QA라고 말하지 않는다. 실제 앱을 열고 동일 시나리오를 수행한 증거가
별도로 필요하다.

## 15. surface 완료 정의

surface 하나가 완료되려면:

- manifest와 mac source link 최신
- 모든 state 구현
- keyboard/pointer/accessibility 명세 통과
- localization 6개 언어 key complete
- persistence/restart scenario 통과
- native request stale/cancel scenario 통과
- 성능 예산과 memory bound 통과
- macOS/Windows side-by-side review 승인
- known delta가 register에 있고 owner/milestone 지정
- code test와 실제 UI QA를 구분해 기록

## 16. 현재 확인된 주의점

- macOS root는 catalog가 blocked이면 recovery view로 전체 workspace를 대체한다.
- selected frame 복구는 ID 존재뿐 아니라 source availability를 본다.
- Develop active tool은 Escape로 crop/brush/region/clone/base-picker/local adjustment를 함께 정리한다.
- 좌우 panel width는 서로 독립적으로 저장한다.
- filmstrip sort/order/scope/height/item scale이 저장된다.
- module 전환 뒤 Develop/Print 선택과 soft-proof refresh를 지연 동기화한다.
- root 전체가 external file drop target이며 drag target feedback이 있다.
- toolbar action과 menu/shortcut enabled 규칙이 같은 AppModel command를 통해 연결된다.

이 동작을 WinUI 화면 모양만 보고 놓치지 않는다.

## 17. 관련 문서

- [feature-map.md](feature-map.md)
- [shell-and-navigation.md](shell-and-navigation.md)
- [application-lifecycle.md](application-lifecycle.md)
- [input-and-shortcuts.md](input-and-shortcuts.md)
- [accessibility-localization.md](accessibility-localization.md)
- [../99-plan/baseline-manifest.md](../99-plan/baseline-manifest.md)
- [swapchainpanel-canvas.md](swapchainpanel-canvas.md)
- [../00-overview/decision-register.md](../00-overview/decision-register.md)
