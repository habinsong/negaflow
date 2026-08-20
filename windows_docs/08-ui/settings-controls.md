# Settings·inspector control 기준

기준일: 2026-08-04  
상태: UI prototype 결정  
상세 화면: [Settings](surfaces/settings.md), [Develop](surfaces/develop.md),
[Export](surfaces/export.md), [Print](surfaces/print.md)

## 1. 목적

macOS Negaflow의 `Form(.grouped)`는 다음 규율을 가진다.

- related control을 section으로 묶음
- label과 control의 정렬을 framework에 맡김
- ordinary control은 rest 상태에서 quiet
- full-width slider track
- path/value는 secondary hierarchy
- custom glass, shadow, pill을 만들지 않음

Windows에서도 이 시각적 밀도와 정보 계층을 유지한다. Windows Community Toolkit의 `SettingsCard`와
`SettingsExpander`는 유력한 도구지만, 모든 inspector row를 카드로 만드는 것이 목표는 아니다.

## 2. dependency 후보

| 항목 | 후보 |
|---|---|
| package | `CommunityToolkit.WinUI.Controls.SettingsControls` |
| namespace | `CommunityToolkit.WinUI.Controls` |
| 사용 언어 | C# WinUI shell |
| 적용 범위 | Settings page와 조건부 subgroup |
| 확정 gate | Windows App SDK 2.3.1/.NET 10/x64/ARM64 prototype + license/SBOM |

Microsoft의 Settings 지침은 Toolkit의 `SettingsCard`/`SettingsExpander` 사용을 권장한다. 그러나 Toolkit은
Windows App SDK 본체가 아닌 별도 dependency다. 정확한 package version, transitive dependency, license,
ARM64 runtime 동작을 lockfile과 build artifact로 확인하기 전 필수 dependency로 확정하지 않는다.

Toolkit을 쓰지 못해도 동일한 시각 계약을 basic WinUI `Grid`, `Border`, `StackPanel`, `ContentPresenter`로
작게 구현할 수 있어야 한다. view model과 setting schema가 Toolkit control type을 public API로 노출하면
안 된다.

## 3. `SettingsCard`

공식 Toolkit control이 제공하는 주요 slot:

- `Header`
- `Description`
- `HeaderIcon`
- `Content`
- clickable navigation mode
- horizontal/vertical content alignment
- adaptive wrapping

Negaflow 사용 규칙:

- 기본 행은 icon 없음
- description은 값의 결과나 위험을 설명할 때만 사용
- `IsClickEnabled`는 detail page/외부 destination 탐색 행에만 사용
- toggle/button 자체가 있는 행 전체를 중복 click target으로 만들지 않음
- right-aligned content가 label을 침범하면 vertical layout으로 전환
- selected/disabled/error state를 card fill 색만으로 표현하지 않음

적합한 예:

- appearance + `ComboBox`
- auto-develop + `ToggleSwitch`
- scanner capability readout
- resolved storage path + action
- support bundle export

부적합한 예:

- Develop의 모든 tone slider를 큰 개별 card로 감싸기
- Library filter chip 하나마다 card 만들기
- canvas HUD
- Print page 내부의 고밀도 geometry editor 전체

## 4. `SettingsExpander`

`SettingsExpander`는 header row와 child `SettingsCard` collection을 한 단계 접고 펼칠 때 사용한다.

적합한 경우:

- soft proof on/off + 활성화 시 profile/simulation/gamut warning
- custom storage mode + 개별 path
- external backup destination + volume/status details
- scanner plugin trust + identity detail
- Legal의 About/dependency 목록

금지:

- 두 단계 이상 nested expander
- 한두 개의 항상 필요한 항목을 기본적으로 숨기기
- error/status를 collapsed content 안에만 두기
- 현재 작업에 핵심인 Develop control을 공간 절약 명목으로 임의 접기

Toolkit 문서에는 parent `StackPanel`에 `MaxWidth`가 있을 때 `ItemsRepeater` 기반 expander의 visual glitch가
생길 수 있다는 주의가 있다. Settings prototype은 해당 조합을 `Grid`로 감싸는 workaround와 최신 package
상태를 함께 검증한다.

## 5. Negaflow의 네 가지 행 형태

### 5.1 value row

```text
Label                                      Value
```

- device capability, profile, last success, cache size
- value는 trailing alignment, 숫자는 tabular/monospaced digit 후보
- 긴 값은 middle truncation + tooltip + accessible full value
- unavailable이면 reason을 두 번째 줄에 표시

### 5.2 action row

```text
Label                              [Secondary] [Primary]
```

- profile change/reset, path change/open, plugin approve
- action 순서는 Windows convention과 위험도 기준
- icon-only action은 tooltip과 automation name 필수

### 5.3 slider row

```text
Label                                               1.25
├──────────────────────────●───────────────────────────┤
```

- label/value는 위, track은 아래 full width
- drag, keyboard nudge, editable numeric value, reset, undo grouping을 reusable composite control로 구현
- screen reader에 min/max/step/value/unit 노출
- drag tick마다 engine render를 무제한 enqueue하지 않음

### 5.4 segmented row

```text
┌────────────┬────────────┬────────────┐
│ Automatic  │ Portrait   │ Landscape  │
└────────────┴────────────┴────────────┘
```

- 2–5개의 짧고 서로 배타적인 값
- selected track/thumb를 항상 유지
- 좁은 폭에서 wrap 금지; 해당 control의 horizontal scroll 또는 `ComboBox` adaptation
- 각 segment가 독립 Tab stop인지 group arrow navigation인지 control pattern에 맞춰 고정

## 6. Settings page와 workspace inspector의 차이

| 기준 | Settings | Develop/Export/Print inspector |
|---|---|---|
| 사용 빈도 | 낮음 | 지속적 |
| 정보 밀도 | 중간 | 높음 |
| 카드 사용 | 가능 | 제한적 |
| 설명 | preference 결과 중심 | 현재 사진/recipe 의미 중심 |
| 펼침 | advanced option에 적합 | 사용 흐름을 방해하지 않을 때만 |
| 저장 | global preference | frame/recipe/workspace state |
| undo | 대체로 없음 | gesture당 하나의 undo 필요 |

`SettingsCard`를 Develop에 그대로 반복하면 vertical space와 visual chrome이 커진다. Develop은 shared
inspector row/section을 기본으로 하고, Toolkit card는 native layout prototype에서 실제 밀도가 맞는 경우에만
쓴다.

## 7. 화면 매핑

| 화면 | control 전략 |
|---|---|
| Settings/General | quiet cards 또는 shared rows + combo/toggle |
| Settings/Memory | mode segment + value rows 또는 full-width sliders |
| Settings/Interface | canvas segment + toggle rows |
| Settings/Scan | capability value rows + supported range sliders |
| Settings/Disk | grouped path rows + conditional custom expander + action row |
| Settings/Export | compact fields + soft-proof expander |
| Settings/Shortcuts | group segment + custom recorder rows |
| Settings/Legal | selectable sections/About expander |
| Develop | custom dense inspector section + reusable slider/value control |
| Export | recipe section + format-specific conditional rows |
| Print | dense layout/content/output sections; paper geometry full-width controls |
| Scanning | capability-driven rows; unsupported option disabled with reason |

## 8. responsive 규칙

- content max width를 두되 page background를 opaque card wall로 만들지 않는다.
- label/control horizontal layout은 localized text 측정 뒤 vertical로 전환한다.
- main action 자체가 잘리는 경우 control을 줄이지 않고 row를 vertical로 바꾼다.
- backup의 명시된 equal-width 3-button row와 shortcut group segment는 wrap하지 않는다.
- path action은 좁은 폭에서 text button보다 icon button을 사용할 수 있지만 accessible name을 유지한다.
- 200/400% text scaling에서 fixed height를 제거하고 minimum height만 둔다.
- scroll viewer 안에 서로 경쟁하는 vertical scroll viewer를 만들지 않는다.

## 9. focus와 keyboard

- visible 순서와 tab order를 일치시킨다.
- label click이 연결 control로 focus를 옮긴다.
- `Space`는 toggle/button, arrow는 radio/segment/slider의 native 의미를 따른다.
- slider의 text editing mode와 canvas accelerator가 충돌하지 않는다.
- expander collapse 시 child에 있던 focus를 header로 되돌린다.
- disabled child는 tab order에서 빠져도 Narrator가 unavailable reason을 읽을 수 있어야 한다.
- destructive confirmation의 default/cancel button을 명시한다.

## 10. 상태 표현

모든 async row는 최소 다음 상태를 model로 가진다.

```text
idle
validating/loading
succeeded(result/evidence)
failed(code, userMessage, recovery)
cancelled
```

- progress spinner를 label 대신 영구 표시하지 않는다.
- success는 짧은 message와 last-success evidence로 남긴다.
- failure는 inline 또는 page `InfoBar`로 보이고 category 전환 후에도 사라지지 않는다.
- retry는 idempotent한 작업에만 제공한다.
- stale async result가 새 path/profile/device row를 덮지 못하도록 request revision을 검사한다.

## 11. styling token

초기 후보는 WinUI theme resource에서 가져온다. pixel number를 제품 전역에 흩뿌리지 않는다.

| token 역할 | 규칙 |
|---|---|
| section header | `BodyStrong` 계열 |
| row label/value | `Body`/`Callout` 계열 |
| help/error | `Caption` 계열 + semantic color |
| row min height | 약 30–32 DIP, text scaling에 따라 증가 |
| group spacing | native Settings sample rhythm에서 prototype |
| row corner/fill | system/Toolkit resource, custom shadow 없음 |
| focus | WinUI native focus visual 유지 |

사진 색을 표현하는 black/gray/white canvas segment나 gamut warning은 system accent token과 별도 semantic
resource로 둔다.

## 12. accessibility gate

Toolkit 문서가 접근성을 목표로 한다고 해도 Negaflow 조합의 검증을 대신하지 않는다.

- Accessibility Insights automated scan
- Narrator name/role/state/value
- keyboard-only completion
- high contrast theme
- 200/400% text scaling
- icon-only action name
- disabled reason
- error announcement
- expander focus restore
- slider editable value와 range pattern
- segment selected state와 group name

custom control은 필요한 automation peer/pattern을 명시적으로 구현한다.

## 13. dependency fallback 기준

다음 중 하나면 Toolkit settings control을 제거하고 local WinUI composition으로 대체한다.

- Windows App SDK 2.3.1 또는 다음 stable patch와 runtime crash/visual corruption
- ARM64 blocker
- accessibility pattern을 고칠 수 없음
- large Settings page에서 unacceptable layout/measure cost
- package licensing/SBOM/release policy와 불일치
- style override가 upstream template 복제 수준으로 커짐

fallback은 디자인 시스템 재창조가 아니다. native `Grid`/`Border`/`ContentPresenter`로 이 문서의 네 가지
행 형태만 구현한다.

## 14. prototype checklist

- General, Disk, Export, Develop 각각 대표 section 1개
- English/Korean/German, RTL pseudo-localization
- 720/960/1440 DIP 폭
- 100/150/200% display scaling
- 200/400% text scaling
- light/dark/high contrast
- mouse/keyboard/Narrator
- path 260자, error 두 줄, disabled reason 세 줄
- expander inside max-width page
- 100회 category switch와 memory/layout profiler
- x64/ARM64 Release build

## 15. 공식 자료

- [Guidelines for app settings](https://learn.microsoft.com/en-us/windows/apps/design/app-settings/guidelines-for-app-settings)
- [SettingsCard](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard)
- [SettingsExpander](https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingsexpander)
- [Keyboard interactions](https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-interactions)
- [Accessibility overview](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview)

