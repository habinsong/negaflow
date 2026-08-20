# Library surface 이식 명세

기준일: 2026-08-04  
소스 근거: `Features/Library` 전체, `AppModel+FrameSelection`, Library persistence/recovery

## 1. 역할

Library는 단순 thumbnail gallery가 아니다.

- 파일·폴더 import와 source folder 관리
- 폴더·film type·offline·all view
- text/query/quick filter
- sort와 card size
- grid/compare/survey culling
- multi-selection과 active frame
- pick/reject/rating
- stack, virtual copy, manual/smart collection, saved search
- duplicate candidate
- rename, move/relink, remove-from-library, source-to-trash
- Develop 진입과 filmstrip interaction scope 생성
- catalog/source recovery

이 surface의 data semantics가 Develop, Export, Print의 대상 집합을 결정한다.

## 2. 레이아웃

```text
┌─────────────────────┬───────────────────────────────────────────────┐
│ 76px tab rail       │ Browser header                               │
│ Import / Files /    ├───────────────────────────────────────────────┤
│ Collections         │ Grid / Compare / Survey                       │
│                     │                                               │
│ resizable controls  │                         view-mode + search     │
└─────────────────────┴───────────────────────────────────────────────┘
```

현재 초기값:

- controls width 430pt
- view `folders`
- film type `colorNegative`
- sort `inputOrder`, ascending
- card scale 1.0
- controls tab `importing`
- culling mode `grid`

Windows에서는 `Grid`의 첫 column + accessible splitter + browser column으로 구현한다. Library의
controls width range는 Develop panel과 별도다.

## 3. controls tab

| tab | 내용 |
|---|---|
| Import | import action/progress, folder selection, current result 연결 |
| Files | source folder tree와 frames |
| Collections | all/manual/smart/saved search organizer |

tab rail:

- 76 effective px 후보
- selected icon state + localized tooltip/name
- header에 tab title과 전체 frame count
- content clip, 독립 scroll
- selected tab은 현재 macOS에서 session state이고 persistence가 관찰되지 않음. Windows에서 저장할지는 delta 결정

## 4. view mode

선언 순서는 사용자 위계다.

| mode | 의미 | folder grouping |
|---|---|---|
| Folders | source folder별 | 예 |
| Film Type | 저장된 film type으로 제한 후 folder별 | 예 |
| Offline | source unavailable만 | 아니요 |
| All | 전체 | 아니요 |

smart collection/saved search를 선택하면 view mode는 All로 바뀌고 folder selection은 해제된다.
stored definition이 active일 때 bottom view/search와 header sort를 직접 편집하지 못하게 하는 현재
규칙을 보존한다. stored definition을 나가려면 header의 명확한 clear/select-all action을 쓴다.

## 5. sort

stable key:

- input order
- time
- name
- flag
- rating
- file size

정렬은 ascending/descending을 함께 저장한다. 동률은 original input order로 안정화한다. file size가
없는 frame은 있는 frame 뒤에 오고 unknown끼리는 original order다. Windows의 locale string sort가
macOS `localizedStandardCompare`와 완전히 같지 않을 수 있으므로 이름 정렬은 제품 delta로 실측하고
natural-number semantics를 테스트한다.

stored smart/search definition이 active면 그 definition의 sort가 effective sort이며 header control은
disabled다.

## 6. search와 quick filters

text input은 75ms debounce 후 query에 적용되고 empty는 즉시 clear된다. Windows에서도 UI thread
마다 전체 projection을 만들지 않고 cancellable debounce를 쓴다.

quick filters:

- current roll
- minimum rating 1~5
- picked
- rejected
- offline
- infrared capture
- defect recipe 있음
- scanner profile unvalidated
- metadata unknown

여러 filter는 `match all`이다. picked와 rejected 둘 다 켜면 pick state의 `isAnyOf` 조건 하나로
결합된다. Offline view에서는 offline quick toggle이 강제된 의미이므로 control을 disabled한다.

Clear All:

- text search clear
- quick filter clear
- organizer `.all`
- view mode까지 무조건 reset하지는 않음

filter popover는 현재 620pt 폭의 horizontal control row다. 좁은 Windows 창에서 wrap하지 않고
horizontal scroll 또는 adaptive flyout width를 사용하되 모든 toggle을 한 줄의 빠른 filter로 유지한다.

## 7. projection과 interaction scope

화면에 보이는 목록과 실제 command 대상이 같은 ordered ID projection을 공유한다.

```text
source frame IDs / organizer
→ query
→ sort
→ folder/film/offline view
→ stack projection
→ ordered interaction scope
→ selection/action/export/filmstrip
```

중복 UUID를 보이면 안 된다. ID가 catalog에서 유일하지 않은 상태는 조용히 한 개를 고르는 대신
진단/복구 대상이다.

scope가 바뀔 때:

- selection을 새 scope와 교집합
- active frame이 살아 있으면 유지
- anchor가 사라지면 surviving active/first selected로 보정
- 모두 사라지면 selection/active/anchor clear
- 다른 folder/filter의 frame을 순간적으로 Develop하지 않음

## 8. selection

Windows 번역:

| 입력 | 동작 |
|---|---|
| plain click | 단일 selection, active/anchor 해당 frame |
| Ctrl-click | toggle membership, active 규칙 보존 |
| Shift-click | anchor~target의 ordered range 선택 |
| right-click | context action 대상 규칙을 명시, 기존 multi-selection 보존 |
| empty background | 제품 결정에 따라 clear, context menu와 충돌 금지 |

active frame과 selected set은 다르다. Compare에서는 active가 candidate 선택에 쓰이고, Print에서는
active와 전체 actionable selection을 함께 쓴다.

선택 frame이 제거되면 현재 scope에서 다음 frame, 없으면 이전 frame을 후보로 한다. 전역 catalog
마지막 frame을 순간적으로 선택하지 않는다.

## 9. Grid

현재 geometry:

- card width `190 × scale`
- thumbnail ratio 3:2
- thumbnail-title spacing 3
- rating row height 14
- scale 0.72~1.42, step 0.08, 100% reset
- grid spacing `max(10, 14 × scale)`
- outer padding 18

WinUI 구현 후보:

- `ItemsView` + `UniformGridLayout` 또는 실제 virtualization이 증명된 custom `ItemsRepeater`
- folder grouping은 section header + nested virtualized layout 또는 flattened item source
- thumbnail decode/cache는 UI element 수명과 분리
- container recycle 시 frame ID, selection, tooltip, image request revision 초기화

현재 SwiftUI `LazyVGrid` 구조를 그대로 nested virtualizing controls로 옮기면 folder 수가 많을 때
virtualization이 깨질 수 있다. Windows data source는 다음처럼 flatten하는 스파이크가 우선이다.

```text
FolderHeaderItem
FrameCardItem
FrameCardItem
FolderHeaderItem
...
```

단, section별 adaptive wrapping과 sticky header가 필요한지 실제 UX를 기준으로 선택한다.

## 10. frame card

표시/상태:

- developed thumbnail when available
- frame display name
- rating 0~5
- pick/reject
- selected/active visual
- offline
- stack count badge
- virtual-copy 구분
- source/progress/error 필요 시

pointer hit targets:

- card selection area
- rating 별
- pick/reject controls
- stack menu/badge
- drag source
- context menu

rating/pick을 누를 때 selection이 의도치 않게 바뀌거나 drag가 시작되지 않게 event routing을
분리한다. card가 recycle된 뒤 이전 thumbnail task가 새 card에 이미지를 적용하지 않도록 frame ID와
thumbnail revision을 commit 직전에 확인한다.

## 11. folder grouping

folder header:

- folder icon/title
- visible frame count
- folder-level development process/target controls
- source drop destination
- new folder, reveal, rename context

폴더 이름이 같은 다른 path를 title만으로 합치지 않는다. normalized full path가 identity다. reparse
point/symlink resolution과 case-insensitive Windows path identity는 persistence 문서에서 별도 정의한다.

folder development controls가 폴더의 frame 전부에 적용되는지 현재 projection의 visible subset에만
적용되는지 소스/테스트 기준으로 고정한다. header count는 stack projection 뒤 visible 수를 보여주되
batch target은 원래 folder frame list를 쓰는 현재 구조를 명시적으로 검증한다.

## 12. Compare

조건: ordered selected frame이 최소 2개.

- active selected frame이 candidate
- candidate와 다른 ordered first selection이 reference
- 정확히 reference/candidate 두 surface 표시
- width가 height의 1.15배 이상이면 좌우, 아니면 위아래
- 각 surface 클릭으로 active 변경
- selected/reference/candidate semantics 접근성 노출
- source offline/render pending/error 각각 표시

selection이 2개보다 적으면 두 장 선택 안내 empty state다. 3개 이상 선택돼도 current active와 첫
다른 selected로 비교하고 나머지는 selection에 남는다.

## 13. Survey

- ordered selected frame 전부
- 없으면 selection 안내
- 1~4 columns: 현재 폭/290으로 계산, 최대 4
- 4:3 surface
- active border/state
- scroll + virtualization

Windows에서는 selected 수가 수천 장일 수 있으므로 `ItemsView` virtualization을 유지하고 full-size
preview를 동시에 요청하지 않는다. viewport 주변 preview만 우선한다.

## 14. organizer

### All

전체 frame, count 표시.

### Manual collection

- ordered frame IDs
- 현재 selection으로 create
- add/remove selected frames
- rename/delete
- collection 삭제와 source/catalog frame 삭제는 별개

### Smart collection

- 저장된 query + sort
- definition decode가 실패하면 warning icon, disabled, 설명
- rename/delete 가능

### Saved search

- 저장된 current query + sort
- decode failure 정책은 smart collection과 동일

선택된 organizer가 삭제/손상되면 `.all`로 복구한다. 이름 중복·빈 이름·길이·case normalization은
mutation layer에서 정의하고 UI만으로 보장하지 않는다.

## 15. stack과 virtual copy

- stack projection이 grid/selection/action order에 일관되게 적용
- badge는 frame count와 accessible name
- stack/create/expand/collapse semantics를 별도 surface spec/test로 관리
- virtual copy는 source를 공유하지만 독립 Develop/Defect recipe를 가질 수 있음
- original root를 library에서 제거할 때 연결된 virtual copies 처리 규칙 보존
- virtual copy만 선택한 경우 source-to-trash 계획은 만들지 않음

source 삭제 UI가 virtual copy 때문에 실제 파일 영향 범위를 축소해 표시하면 안 된다.

## 16. context menu

주요 명령:

- stack operations
- Develop 열기
- rename
- rating
- pick/clear, reject/clear
- add/remove manual collection
- create virtual copy
- source offline이면 Locate Original
- Explorer에서 표시
- Remove from Library
- Move Source to Recycle Bin — plan이 있을 때만

multi-selection context:

- clicked frame이 selection 안이면 현재 selected frames
- 아니면 clicked frame 한 장
- ordered scope 안에서 대상 순서 보존
- 메뉴를 열며 selection을 파괴하지 않음

Windows Explorer reveal은 파일이 없을 때 오류/Locate 경로로 연결한다.

## 17. remove와 source deletion

두 동작을 반드시 분리한다.

### Remove from Library

- source 파일을 건드리지 않음
- catalog undo/redo 가능
- 관련 selection, roll, stack, collection membership snapshot
- original root 제거 시 관련 virtual copies 포함 규칙
- cached pixels/thumbnail/task 정리
- undo 가능 기간에는 defect sidecar 보존

### Move Source to Recycle Bin

- virtual copy/preview는 직접 source 삭제 요청을 만들지 않음
- 같은 source를 공유하는 모든 catalog frame과 IR URL을 plan에 포함
- 사용자 확인에 frame 수, source 수, 첫 path 표시
- plan을 commit 직전 현재 catalog와 다시 검증
- 파일을 Recycle Bin에 stage
- candidate catalog snapshot을 원자 commit
- commit 실패 시 파일 rollback
- rollback 실패를 숨기지 않음
- 성공 후 catalog undo history 무효화
- app-owned sidecar/cache purge

Windows 구현은 `IFileOperation` 또는 Recycle Bin API를 검토하되 같은 transaction 의미를 유지한다.
삭제 전에 reparse point와 volume identity를 검증한다.

## 18. source offline와 relink

- thumbnail/metadata가 있더라도 original 필요 command는 disabled/relink 요구
- Locate Original은 source identity·metadata·hash 정책으로 검증
- relink가 `rawScanURL`을 바꾸는 허용된 명시적 경로
- 다른 source로 잘못 연결하면 기존 recipe를 적용하지 않음
- external drive mount/unmount/drive-letter change 감지
- Windows path가 바뀌어도 volume/file identity로 recovery 후보를 찾을 수 있게 함

offline quick filter와 Offline view는 동일 source-availability truth를 쓴다.

## 19. import

- Images와 Folder entry
- window drag-and-drop
- supported format probe
- duplicate/source identity 정책
- per-item progress와 partial failure
- import order가 inputOrder 기준
- default auto-develop는 explicit persisted setting, 기본 OFF
- original 불변
- folder creation/import transaction
- cancellation 뒤 이미 commit된 항목과 미commit 항목 구분

Import UI가 file picker 결과를 바로 catalog에 append하지 않고 IO probe→validation→transaction을
거친다.

## 20. duplicates

duplicate candidate scan은 실제 삭제 자동화가 아니다.

- current ordered projection을 입력
- candidate 근거와 source identity 표시
- user가 비교/결정
- virtual copy와 byte-identical source를 구분
- hash/metadata/visual similarity의 증거 수준 구분
- scan cancel/progress
- 삭제는 별도 Remove/Recycle transaction 사용

## 21. empty/error/recovery

| 상태 | UI |
|---|---|
| catalog empty | Import Images primary action |
| query result empty | No matching photos + Clear Filters |
| compare <2 | 두 장 선택 안내 |
| survey empty | 사진 선택 안내 |
| stored query invalid | disabled row + warning/help |
| source offline | card state + Locate Original |
| catalog blocked | Library 내부가 아니라 root recovery workspace |
| thumbnail failure | card placeholder, source 자체 손상과 구분 |
| mutation locked | 관련 commands disabled + 이유 |

## 22. 성능 기준

실측 전 수치를 임의 확정하지 않지만 다음 시나리오를 통과해야 한다.

- 50,000 frame catalog projection/scroll
- 5,000 folder/collection rows의 lazy loading
- 75ms search debounce 중 stale result 억제
- card scale 변경 중 header/grid 흔들림 없음
- sidebar resize 중 browser header 수평 점프 없음
- selection 1/100/5,000 items
- survey viewport preview bound
- source mount/unmount refresh
- background thumbnail이 Develop slider를 방해하지 않음

projection과 selection은 ID array/set 중심으로 유지하고 SwiftUI처럼 모든 `ScanFrame` reference를
managed UI collection에 매번 복제하지 않는다.

## 23. 접근성

- grid/list selection container와 item SelectionItem
- active vs selected를 value/help로 구분
- card name, rating, flag, online/offline
- folder expand/collapse/selection
- filter toggle/rating minimum
- culling mode selection
- Compare reference/candidate
- scale/sort/view mode current value
- drag/drop 대체 menu commands
- destructive confirmation의 명확한 범위

## 24. acceptance

- 모든 view/sort/filter 조합에서 ordered result와 action scope 일치
- Ctrl/Shift selection과 active/anchor 복구
- stored smart/search definition invalid 처리
- grid/compare/survey 전환 후 selection 보존
- folder grouping/stack/virtual copy count 정확
- card recycle에서 thumbnail·selection leakage 없음
- Remove는 source를 보존하고 undo됨
- Recycle은 full impact plan, rollback, undo invalidation을 수행
- offline/relink/restart 후 source state 일관
- 50k virtualization, 6개 locale, 200% text, Narrator 핵심 경로

## 관련 공식 참고

- [ItemsView](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.controls.itemsview)
- [ItemsRepeater](https://learn.microsoft.com/en-us/windows/apps/design/controls/items-repeater)
- [TreeView](https://learn.microsoft.com/en-us/windows/apps/design/controls/tree-view)
- [Drag and drop](https://learn.microsoft.com/en-us/windows/apps/design/input/drag-and-drop)

