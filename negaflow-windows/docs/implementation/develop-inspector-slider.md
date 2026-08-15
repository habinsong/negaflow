# Develop inspector 공통 slider control

기준일: 2026-08-09  
macOS 기준: `BaseControlSection.swift`, `InspectorSlider.swift`,
`EditableSliderValueText.swift`, `ResettableSlider.swift`, `DevelopKeyboardNudge.swift`

## 이번 범위

`Views/Controls/InspectorSlider`는 label, 우측 54 DIP 편집값, slider를 하나의 재사용 가능한
control로 묶습니다. 연결 지점은 `Exposure`와 현재 지원되는 수동 Base R/G/B입니다. 이 UI 범위는
catalog, C ABI, recipe, preview/export 수식 및 persistence를 바꾸지 않습니다.

- value는 engine의 최소/최대 범위를 유지하고, 직접 입력은 부호가 있는 십진수만 허용합니다.
  범위 밖, `NaN`, `Infinity`, 지수 표기는 현재 value를 바꾸지 않습니다.
- Arrow는 0.01, Shift+Arrow는 0.10 step으로 2자리에서 반올림·clamp합니다. Exposure만
  double-click reset을 제공하고, macOS 수동 Base R/G/B와 같이 Base controls에는 reset이 없습니다.
- 안정된 slider AutomationId는 `negaflow.develop.exposure`와
  `negaflow.develop.base.red/green/blue`를 제공합니다. label, 현재값, range와 keyboard 도움말은
  slider에 노출합니다. 값 editor와 display는 같은 `.value` ID, label 연결 및 입력 범위 HelpText를
  제공합니다.
- normal value는 light/dark theme의 primary text brush를 사용하고, 잘못된 draft만 빨간색으로
  표시합니다. invalid input은 변경을 적용하지 않고 beep와 오류 HelpText를 내보내며, 다음 입력에서
  정상 상태로 돌아갑니다. 기존 Exposure가 숨기던 thumb tooltip도 숨깁니다.
- `Enter` 또는 실제로 수정한 draft의 focus-loss만 commit합니다. 변경하지 않은 draft와 `Escape`는
  현재 값을 유지한 채 editor를 닫습니다.

## 의도적으로 남긴 범위

`CurveHighlights/Lights/Darks/Shadows`는 macOS Parametric Tone Curve의 별도 recipe이므로 Basic Tone으로
표시하지 않습니다. Basic Tone은 ABI 0.9 `nf_develop_export_v3`/`nf_develop_preview_v3`의 별도 append-only
필드로 전달합니다.

`BaseControlSection`도 Auto/Film/Manual mode와 film stock·light source·scanner profile picker가
필요합니다. 기존 Dmin RGB 3개를 그 section의 대체물로 취급하지 않습니다.

## 검증

- `dotnet build .\\src\\Shell\\Negaflow.Shell.csproj --configuration Debug -p:Platform=x64 --no-restore`
  — warning 0, error 0.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\test-managed.ps1 -Preset x64-debug`
  — Catalog 314 assertions, Shell 209 assertions 통과.
- `powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\test.ps1 -Preset x64-debug`
  — native CTest 30/30 통과.
- x64 Debug WinUI 앱을 실제 렌더했습니다. empty/imported 상태와 Exposure normal state를 확인했고,
  focus한 slider에서 `Right`가 `-1.00`을 `-0.99`로 바꾸는 것을 확인했습니다. 수동 Base
  Red도 `Right`로 `0.00`에서 `0.01`로 바뀌고 Export 가능 상태로 전환되는 것을 확인했습니다.

코드는 value editor의 AutomationId/name/label/HelpText와 invalid draft focus 복귀를 설정하지만,
실제 UI Automation tree, double-click reset, high contrast, compact 폭 및 ARM64 runtime은 이번 증거
범위에 포함되지 않습니다.
## 2026-08-09 Basic Tone vertical slice

macOS `basicToneSection` 순서대로 `Exposure`, `Contrast`, `Highlights`, `Shadows`, `Whites`, `Blacks`, `Density`를 같은 `InspectorSlider` composite로 배치했습니다. stable slider IDs는 `negaflow.develop.exposure`, `.contrast`, `.highlights`, `.shadows`, `.whites`, `.blacks`, `.density`입니다. positive/digital frame에서는 Shell state와 visible controls 모두 tone mutation을 거부합니다.

Catalog은 macOS key `density`, `highlight`, `shadow`, `whites`, `blacks`를 missing=0 규칙으로 읽고 unknown params를 보존한 채 왕복합니다. ABI v2의 `highlights/lights/darks/shadows`는 Parametric Tone Curve 계약으로 동결하고, ABI 0.9 v3에 Basic Tone 다섯 값을 append했습니다. preview와 export는 같은 v3 request를 사용하며 native `BasicToneParameters`로 전달됩니다.

x64 Debug 검증은 native CTest 30/30, Catalog 317 assertions, Shell 248 assertions, interop 52 assertions(ABI 0.9)입니다. native ABI test는 Basic Tone v3 preview가 neutral preview와 다른 pixels를 내는지 확인합니다. computer-use로 Debug Shell을 시작해 `negaflow` 창을 관찰했지만, state/capture 호출이 `node_repl exec context not found`로 실패했습니다. 따라서 이 일곱 control의 rendered screenshot, UIA tree, keyboard/focus, high contrast/compact/ARM64 runtime은 미검증입니다.

## 2026-08-09 Parametric Tone Curve control slice

`ToneAdjustment`의 기존 `curveHighlights`, `curveLights`, `curveDarks`, `curveShadows`를 macOS
`toneCurveSection`의 순서대로 별도 `Tone curve` Inspector 그룹에 연결했습니다. 각각의 slider는
`negaflow.develop.curve.highlights`, `.lights`, `.darks`, `.shadows` AutomationId를 사용하고,
기존 native parametric-curve request fields를 그대로 preview/export에 전달합니다. Basic Tone의
`Highlights`와 `Shadows`와는 레시피·UI 그룹·ABI field가 분리되어 있습니다.

Shell state는 네 값을 엔진 `MaximumToneControl` 범위로 clamp하고, positive/digital frame에서
수정 요청을 거부합니다. x64 Debug 관리형 검증은 warning/error 0, Catalog 317 assertions와 Shell
255 assertions를 통과했습니다. 이는 Slider의 값 변경과 상태/요청 경로 검증만 포함합니다.
macOS `ToneCurveEditor` 캔버스, rendered screenshot/UIA/focus/keyboard/high-contrast/compact/ARM64
runtime 증거는 아직 없습니다.

## 2026-08-09 Develop inspector 구조·히스토그램 체크포인트

고정 macOS 기준 `2fa1d6297378673b58b8bec72025e968ccc3125c`와 사용자 제공
`negaflow_mac_screenshot/develop_right_basic_restored.png`,
`develop_right_base_panel.png`를 기준으로 오른쪽 Inspector의 첫 구조 결함을 닫았습니다.

- 순서는 `Histogram → Basic/Base/Edit/Defects/Info/Reset → tab content → common adjustments`입니다.
- Histogram은 118 DIP 한 카드에서 64-bin luma/R/G/B, clipping channel, Shadow/Density/Exposure/Highlight
  네 영역을 표시하고 pointer drag와 keyboard 조정을 같은 Basic Tone recipe에 연결합니다.
- Inspector `ScrollViewer`, 카드, disclosure header, content, composite slider를 모두 가용 폭에
  stretch했습니다. 카드의 macOS 14 DIP 내부 inset만 남고 별도의 좌측 정렬 column은 없습니다.
- macOS 카드 하나당 WinUI visual surface도 하나입니다. disclosure를 위해 기본 `Expander`나 두 번째
  card를 중첩하지 않고, 단일 `Border` 안의 `DisclosureButton`이 펼침 상태를 제어합니다.
- Tone만 기본 확장되고 한 번에 한 section만 확장됩니다. header는 UIA
  `ExpandCollapsePattern`과 상태 변경을 제공합니다.
- Histogram, tab, section, reset, 접근성 도움말은 `de-DE`, `en-US`, `fr-FR`, `ja-JP`, `ko-KR`,
  `zh-Hans` 리소스로 분리했습니다. 사용자 표시 한국어를 C#/XAML에 직접 넣지 않습니다.

실제 x64 Debug 창을 150% DPI에서 측정한 결과 Histogram/Tone/Tone Curve/Color Mixer/Color Grading
카드는 모두 `left=3207, width=603` physical pixel이었습니다. Exposure slider는 카드 내부 14 DIP
inset 뒤 `left=3228, width=561`이었고, Tone Curve header의 UIA state는
`Collapsed → Expanded`로 바뀌면서 Tone 카드 높이 81, Tone Curve 카드 높이 967이 됐습니다.

이 체크포인트는 전체 Inspector 완료가 아닙니다. Edit/Defects/Info/Reset의 고유 tab content,
Color/BW Toning/Calibration/Detail sections, tab Selection pattern, tool-state 취소, compact/high contrast,
실제 ARM64 runtime은 남아 있습니다. 최신 사용자 우선순위에 따라 이 UI 확장은 보류하고
`docs/progress/next-steps.md`의 backend 순서로 전환합니다.
