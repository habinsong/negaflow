# 접근성·현지화·타이포그래피 명세

기준일: 2026-08-04  
현재 자산: Localization Swift 7,929줄, system + 6개 명시 언어

## 1. 지원 언어

| stable locale ID | 표시 이름 | fallback |
|---|---|---|
| `system` | System 또는 해당 UI 언어 번역 | OS 언어 해석 |
| `en` | English | 최종 fallback |
| `ko` | 한국어 | English |
| `ja` | 日本語 | English |
| `zh-Hans` | 简体中文 | English |
| `fr` | Français | English |
| `de` | Deutsch | English |

시스템 언어 해석은 macOS와 같은 우선순위를 유지한다. 지원하지 않는 locale이면 English다.
`zh`는 v1에서 Simplified Chinese로 해석하되 script/region qualifier가 있는 경우 Windows resource
resolution 결과를 테스트한다.

## 2. 자산 이관 방식

Swift source를 런타임에 파싱하거나 UI 구현자가 문자열을 손으로 옮기지 않는다.

```text
AppLocalizedText / AppLocalizedPhrase / Accessibility phrase tables
→ 중립 localization manifest
→ placeholder·key completeness validation
→ locale별 .resw
→ MRT Core resource lookup
```

manifest 필드:

```text
stable_key
category
developer_comment
English source
locale values
placeholder names/types/order
accessibility_only
surface owners
deprecated_since
```

`AppLocalizedText`와 `AppLocalizedPhrase`가 같은 visible string을 표현하더라도 자동으로 key를
합치지 않는다. context, grammar와 future copy ownership이 같은지 검토한다.

## 3. build-time localization gate

각 locale에서 검사:

- 모든 active key 존재
- 빈 값이 의도된 것인지 allowlist
- placeholder 수·이름·type 일치
- format brace/percent escaping
- leading/trailing whitespace
- newline/tab policy
- duplicate semantic key 후보 report
- untranslated English copy heuristic
- raw enum key가 UI fallback으로 노출되지 않음
- accelerator marker와 literal ampersand
- unsupported markup/HTML 없음
- Unicode normalization과 invalid surrogate 없음

English fallback은 사용자 crash를 막는 runtime 안전망이지 번역 누락을 합격시키는 수단이 아니다.

## 4. format 문자열 변환

현재 Swift 표에는 `%d`, `%@`, `String(format:)` 계열이 있다. Windows의 `{0}` style로 단순 search/
replace하지 않는다.

예:

```text
mac source: Point %d of %d, input %d percent, output %d percent
manifest:   Point {pointIndex} of {pointCount}, input {inputPercent} percent, ...
```

generator가 locale별 placeholder 이름과 type을 검증하고 C#의 typed formatting call을 만든다.

규칙:

- 사용자 숫자: current locale number formatter
- 파일 format, JSON, manifest, hash: invariant culture
- DPI, mm, inch, percent: 단위와 숫자를 locale-aware resource로 조합
- EXIF technical values: unit는 안정적으로, decimal separator는 UI locale
- path/file name/profile name/device model: 번역하지 않음
- plural/개수: 단순 English `s` 붙이기 금지, locale별 form 설계

## 5. 앱 언어 변경

Settings에서 system/6개 언어를 선택한다.

필수 동작:

- 선택 저장
- resource context 갱신
- main menu, toolbar, view, dialog, tooltip, automation name 함께 갱신
- 현재 text edit와 unsaved recipe 보존
- runtime 완전 갱신이 안전하지 않은 control은 명시적 재시작 안내
- 재시작이 필요해도 선택이 다음 실행에 확실히 적용
- locale 변경을 catalog data migration으로 취급하지 않음

WinUI/MRT Core에서 root visual을 재생성할 때 native image session과 export/scanner job을 파괴하지
않도록 Shell resource context와 engine lifetime을 분리한다.

## 6. 번역하지 않는 문자열

- file/folder path와 file name
- ICC profile 이름과 ID
- scanner/backend/plugin ID
- camera/scanner model
- JSON key, schema version, hash, build ID
- image format 명칭: TIFF, JPEG, PNG, DNG
- queue label, ETW event name, diagnostic field key
- exact OS error code/HRESULT
- 사용자 입력 preset/collection/template 이름

사용자에게 보이는 설명 문장과 field label은 번역한다. 기술 값을 설명 없이 그대로 던지지 않는다.

## 7. layout localization

각 surface를 모든 locale에서 다음과 함께 검사한다.

- 100/125/150/200% DPI
- Windows text size 100/150/200%
- 좁은·일반·넓은 panel
- light/dark/high contrast

규칙:

- 중요한 label을 0.92보다 더 작게 축소해 숨기지 않는다.
- ellipsis가 허용된 항목은 tooltip/accessible name에 전체 문자열 제공
- button text가 길어져도 primary action 의미 보존
- German/French 긴 copy에서 control이 겹치지 않음
- CJK glyph fallback과 line height 검증
- monospaced digit은 수치 정렬에만 사용
- fixed pixel width는 실제 content contract와 함께 검증
- segment label이 잘릴 때 icon-only로 조용히 바꾸지 않음

## 8. UI Automation 기본 계약

모든 interactive element는 다음을 갖는다.

- localized accessible name
- 올바른 control type/role
- 현재 value 또는 selection/toggle state
- enabled/offscreen/focusable state
- 관련 label 관계
- 필요한 help text
- stable nonlocalized AutomationId — 테스트·지원용

visible text가 충분한 native control은 이름을 중복 덮어쓰지 않는다. icon-only, canvas custom control,
selected state, unusual composite control에 명시적 semantics를 추가한다.

## 9. custom control별 Automation pattern

### Workspace tab/module

- SelectionItem pattern
- selected/not selected
- Library/Develop/Print name
- 선택 시 focus와 visual selection 동기화

### panel toggle

- Toggle pattern
- On/Off
- sidebar/filmstrip/inspector name
- hidden panel descendant는 UIA tree에서 offscreen focus target이 되지 않음

### Library card·filmstrip item

- SelectionItem
- multi-select container 관계
- frame display name
- source online/offline
- rating 0~5, pick/unflagged/rejected, virtual-copy/stack state
- thumbnail decorative image는 중복 읽지 않음
- context menu와 default action

### folder tree

- TreeItem + ExpandCollapse + SelectionItem
- folder name, item/child count 필요 시
- expanded state 저장과 UIA state 일치
- virtualization 후 realize/scroll into view
- file row와 folder row의 role 구분

### inspector slider

- RangeValue pattern
- localized name, current formatted value, min/max/small/large change
- reset는 별도 Invoke button
- editable numeric field는 Value pattern
- drag와 keyboard nudge가 하나의 undo gesture라는 내부 동작은 screen reader에 불필요

### segmented control

- radio/selection container semantics
- 각 option name과 selected state
- color만으로 선택 표시 금지

### tone curve

custom AutomationPeer 필요:

- control name: Tone Curve
- 전체 point 수와 selected point
- point별 input/output percent
- previous/next/add/delete action
- arrow-key move와 직접 NumberBox edit
- curve 자체 visual은 이미지 설명으로 과도하게 읽지 않음

### histogram

- name과 현재 sampled region/summary
- RGB/channel overlay toggles는 selection/toggle semantics
- 모든 bin을 수천 항목으로 읽지 않음
- 필요하면 shadow/mid/highlight 요약 또는 focus sample value

### crop overlay

- image 내 X/Y/width/height percent
- aspect lock state
- move/resize handle의 accessible name
- keyboard nudge와 value fields
- zoom/display coordinate가 아닌 source-normalized 값

### compare divider

- RangeValue: 0~100%, current fraction
- keyboard left/right/home/end
- vertical/horizontal mode name

### Defect brush/clone/region

- active tool과 instruction을 알림
- brush size/feather/opacity RangeValue
- clone source set/unset state
- stroke canvas에 keyboard 완전 등가가 어려운 부분은 region/coordinate numeric 대안 제공
- destructive/commit/cancel 명령을 명확히 노출

### Print canvas

- page list와 current page
- page previous/next
- cell ID, source photo, x/y/width/height
- move up/down, duplicate/delete
- zoom RangeValue
- page pixel preview 자체는 하나의 설명 가능한 image

### Flatbed scan area

- frame number와 film format
- selection
- normalized X/Y/width/height
- add/remove/move/resize keyboard 대안
- hardware applied ROI가 preview overlay와 같은지 상태 설명

## 10. 접근성 상태 용어

현재 macOS는 다음을 6개 언어로 별도 관리한다.

- selected/not selected
- on/off
- active/inactive
- blocked
- select/activate/deactivate
- turn on/turn off
- input/output
- point/region navigation
- crop/filmstrip geometry

Windows에서 control type이 이미 상태를 읽어주는데 accessible name에 “선택됨”을 중복 붙이지
않는다. 값과 action hint는 UIA pattern이 부족한 custom control에만 보충한다.

## 11. focus

- logical reading order와 visual order 일치
- custom title bar에서 content로 예측 가능한 이동
- modal/flyout close 후 invoking control 복귀
- virtualized item focus가 recycle된 container와 섞이지 않음
- selection 변경 때문에 focus가 매번 canvas/root로 튀지 않음
- hidden/collapsed panel descendant focus 제거
- error help text는 관련 input과 연결
- validation 실패 시 첫 invalid control로 이동하되 user text 보존
- blocking recovery는 background workspace로 focus가 빠지지 않음

TabIndex를 모든 element에 하드코딩해 유지보수하는 대신 visual tree와 logical grouping을 먼저
바르게 구성하고 예외만 명시한다.

## 12. Narrator live region

알릴 것:

- import/scan/export/print job 시작과 단계 변경
- terminal success/cancel/failure
- catalog blocked/recovery 결과
- source relink 결과
- device lost와 software fallback
- shortcut recorder accepted/rejected
- background operation이 사용자 action을 막는 이유

알리지 않을 것:

- slider drag의 모든 preview tick
- progress 1%마다
- thumbnail 하나 완료할 때마다
- pointer hover
- 렌더 tile 내부 단계

progress는 rate-limit하고 `N of M`, 단계, terminal을 중심으로 한다.

## 13. high contrast·색 이외 상태

- system high-contrast theme resource 사용
- custom canvas overlay의 line/handle이 배경과 충분히 구분
- selected state에 색뿐 아니라 stroke/icon/shape/automation state
- pick/reject/rating에 icon/text semantics
- histogram channel은 color + label/pattern/selection control
- gamut warning은 color만이 아니라 toggle/status label
- disabled opacity만 지나치게 낮추지 않음
- custom acrylic/glass가 high contrast에서 opaque surface로 대체

이미지 pixel 자체의 색을 high contrast theme로 바꾸지 않는다. chrome과 overlay만 접근성에 맞춘다.

## 14. 모션·투명도·깜박임

- Windows animation setting이 off면 module/panel decorative transition 제거
- blinking progress 또는 rapidly pulsing overlay 금지
- scanner lamp/phase를 animation만으로 전달하지 않음
- transparency/advanced effects가 off면 panel surface를 opaque로
- animation 제거가 완료 event나 focus timing을 바꾸지 않음
- before/after flash나 defect mask blink가 필요하면 사용자 제어와 frequency 제한

## 15. text scaling과 target size

- 200% text에서 command와 current value 접근 가능
- fixed-height row가 text를 clip하지 않음
- inspector slider는 label/value/control이 필요한 경우 vertical stack으로 reflow
- tab rail icon에는 tooltip·name이 있어야 하며 text scale에서 label 완전 유실을 검토
- pointer target은 Windows 권장 최소를 따른다.
- dense photo UI라도 resize splitter/curve point/crop handle의 실제 hit target을 visual보다 넓게 제공

## 16. 오류·help copy

오류는 다음 구조다.

```text
무엇이 실패했는가
현재 데이터는 안전한가
사용자가 할 수 있는 다음 행동
필요할 때만 기술 detail 펼치기
```

- raw HRESULT만 표시하지 않음
- source path는 필요한 상황에서만 표시하고 support bundle에서 redact 가능
- “Unknown error”를 정상 fallback으로 사용하지 않음
- disabled command의 reason은 가까운 help/tooltip에 제공
- scanner capability가 없으면 거짓 control을 disabled로 두기보다 숨김/설명 정책을 surface별로 적용

## 17. AutomationId migration

현재 macOS identifier에서 관찰된 핵심 의미:

- `negaflow.main`, `negaflow.canvas`
- `negaflow.workspace.library/develop/print`
- `negaflow.panel.sidebar/filmstrip/inspector`
- `negaflow.scan`, `negaflow.scanner.rescan`
- `negaflow.quick-export`, `negaflow.export`
- `negaflow.frame-card`, folder/file rows
- `negaflow.filmstrip.scope`, filmstrip resize
- Settings window와 8개 tab pane
- Print canvas/zoom/page/inspector tabs/layout controls
- catalog recovery/restore/export/confirm

Windows AutomationId는 case와 separator를 하나로 정하고 migration manifest에서 원래 의미와
연결한다. dynamic item ID에 사용자 file path를 넣지 않는다. frame UUID가 필요한 test ID는
private test fixture에서만 안정적으로 사용한다.

## 18. 현지화·접근성 테스트 matrix

### 자동

- locale별 resource completeness/placeholder/type
- 모든 AutomationId unique within relevant scope
- interactive element name/control pattern
- tab/focus smoke
- text clipping/overlap heuristic at 200%
- high-contrast resource 누락
- live region flood rate
- keyboard-only golden workflow

### 수동

- Narrator로 Import→Develop→Export
- Library grid/compare/survey selection
- Tone curve와 crop keyboard alternative
- Defect tool instruction/commit/cancel
- Print page/cell editing
- Scanner preview/ROI/progress
- recovery dialog/surface
- 6개 locale와 US/Korean/Japanese/Chinese/German/French keyboard
- light/dark/high contrast, 200% text, Reduce Motion

## 19. 완료 게이트

- active localization key 100%가 6개 locale에 존재
- English/raw key fallback screenshot 0개
- P0/P1 Accessibility Insights issue 0개
- Narrator 핵심 workflow blocker 0개
- keyboard-only core workflow 완료
- custom Canvas/ToneCurve/Crop/Print/Scan controls의 AutomationPeer 승인
- high contrast와 200% text에서 기능 유실 0개
- language change/restart에서 catalog·recipe·job 상태 손실 0개

## 공식 참고

- [Localize Windows apps](https://learn.microsoft.com/en-us/windows/apps/design/globalizing/manage-language-and-region)
- [MRT Core overview](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/mrtcore/mrtcore-overview)
- [Accessibility overview for Windows apps](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview)
- [Custom automation peers](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/custom-automation-peers)
- [High contrast themes](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/high-contrast-themes)

