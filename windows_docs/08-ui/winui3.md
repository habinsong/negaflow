# WinUI 3 플랫폼 기준

기준일: 2026-08-04  
상태: 채택  
관련 결정: [decision register](../00-overview/decision-register.md),
[language decision](../09-language-choice/language-decision.md),
[UI parity contract](parity-contract.md),
[application lifecycle](application-lifecycle.md)

## 1. 결정

Negaflow Windows UI는 Windows App SDK의 WinUI 3로 새로 작성한다.

- UI: C#/.NET 10 + WinUI 3 XAML
- image/render engine: C++20
- 경계: 좁은 versioned C ABI
- canvas: `SwapChainPanel` + Direct3D/Direct2D
- 배포 기준 후보: unpackaged, self-contained, 전통 installer
- API 하한 후보: Windows 11 24H2 build 26100
- 고객 지원 OS: Stable 시점에 지원 중인 Windows 11 release를 별도 확정

Windows App SDK 자체는 Windows 10 1809부터 동작할 수 있지만, 이것이 Negaflow의 지원 OS 약속은 아니다.
색관리, modern picker, GPU/driver QA, ARM64 유지 비용을 고려해 제품 지원 범위는 더 좁게 시작한다.
2026-08-04 기준 24H2 Home/Pro는 2026-10-13 지원 종료이므로 API 하한과 출시 지원 목록을
같은 값으로 고정하지 않는다.

## 2. 왜 WinUI 3인가

Microsoft는 Windows App SDK를 새 Windows desktop app의 권장 개발 플랫폼으로 안내하고, WinUI 3를 그 안의
native UI framework로 제공한다. C#과 C++ 두 projection을 공식 지원하지만 Negaflow는 view model과 일반
desktop orchestration에 C#을, pixel engine에 C++을 쓴다.

이 선택의 제품상 이유:

- Windows 11의 native control, input, focus, accessibility, theme를 직접 사용
- web runtime과 UI process를 추가하지 않음
- `SwapChainPanel`을 통해 native D3D presentation 연결
- `ItemsView`, `TreeView`, `NavigationView`, `InfoBar`, `ContentDialog` 같은 desktop UI building block
- x64와 ARM64를 같은 shell source로 빌드
- AppWindow, app lifecycle, resource/localization, deployment API를 동일 SDK에서 사용

macOS SwiftUI view code의 공유율은 사실상 0%다. 공유 대상은 pixel semantics, domain schema, preset/profile
data, scanner JSON protocol, localization key와 test fixture다. UI framework를 공유하려고 Qt/Electron/MAUI를
고르는 것은 이번 목표와 맞지 않는다.

## 3. 현재 version baseline

2026-08-04 공식 release channel 기준:

| 항목 | 기준 |
|---|---|
| Windows App SDK stable | 2.3.1, 2026-07-16 release |
| servicing family | 2.0, current |
| end of servicing | 2027-04-29 |
| .NET | 10 LTS, latest serviced patch 고정 |
| SDK channel | Stable only |

production build에 Preview/Experimental channel을 넣지 않는다. 실험 API는 isolated spike에서만 평가하고,
stable replacement 또는 자체 구현이 없으면 feature를 release scope에서 제외한다.

dependency lock 원칙:

- central package version 파일에 exact Windows App SDK patch 고정
- CI와 release machine의 .NET/Windows SDK/VS toolchain manifest 고정
- monthly servicing review로 security/reliability patch 평가
- patch 승격 전 x64/ARM64 UI smoke, canvas present, picker, packaging 회귀 실행
- current family의 servicing 종료 최소 90일 전에 다음 stable family upgrade 착수

개발 환경의 구체 version은 [development environment](../13-build-and-deps/development-environment.md)를
단일 truth로 사용한다.

## 4. 지원되는 것과 확인해야 할 것

### 4.1 채택 가능한 stable surface

- WinUI 3 XAML controls와 resource system
- `AppWindow`/windowing
- app instancing과 activation
- `SwapChainPanel`
- Windows App SDK 1.8+ desktop file/folder/save picker
- `ItemsView`와 `UniformGridLayout`/`LinedFlowLayout`/`StackLayout`
- UI Automation 기반 accessibility
- packaged/unpackaged deployment

### 4.2 framework가 대신 해결하지 않는 것

- exact color-managed photo rendering
- ICC/ICM validation과 proof transform
- large-image tile scheduling과 cache budget
- custom curve/crop/brush/clone-stamp interaction
- shortcut recorder와 conflict policy
- scanner plugin trust/sandbox/process protocol
- crash-safe catalog/export/backup transaction
- printer driver의 color management와 printable area 차이

WinUI control을 썼다는 사실만으로 photo app의 성능·정확도·접근성이 검증되지는 않는다.

### 4.3 알려진 tooling/control gap

공식 migration 문서는 Windows App SDK 2.0 시점에도 WinUI 3 project의 Visual Studio XAML Designer
Design tab을 지원하지 않는다고 명시한다. 따라서 개발 workflow는 design-time screenshot이 아니라 다음을
기준으로 잡는다.

- runtime XAML hot reload/runtime tools
- deterministic sample catalog
- visual regression screenshot
- UI Automation tree snapshot
- keyboard/Narrator/manual scaling QA

first-party `DataGrid` 같은 일부 control도 없다. Negaflow 핵심 UI는 photo grid/tree/inspector이므로 즉시
blocker는 아니지만, 단순히 존재한다고 가정하지 않는다.

## 5. 대안 판단

| 후보 | 판단 |
|---|---|
| WinUI 3 | 채택. 새 native Windows desktop UI와 D3D canvas 연결 |
| WPF | mature fallback이지만 신규 제품의 native Windows 11 UI 목표와 우선순위가 맞지 않음 |
| Win32 custom UI | pixel canvas 일부에는 필요하지만 전체 control/accessibility를 직접 만들 이유 없음 |
| Uno Platform | 다중 플랫폼 UI 공유가 요구사항이 아님 |
| .NET MAUI | mobile/cross-platform shell이 요구사항이 아님 |
| Qt | UI 코드 공유보다 두 플랫폼의 native UX가 중요 |
| Electron/Blazor Hybrid | browser/runtime 계층을 추가하며 native canvas·input·memory 목표와 맞지 않음 |

WPF는 비상 대안이지 병렬 구현 target이 아니다. WinUI에서 특정 control이 부족하면 그 control만 native
custom control 또는 Win32 interop으로 보완한다.

## 6. shell 구성

```text
Negaflow.App                    C# WinUI executable
  MainWindow                    workspace shell
  SettingsWindow               single-instance settings AppWindow
  ViewModels                    UI state/adapters only
  Services                     picker, activation, dispatcher, localization
  Interop                      generated/handwritten safe C ABI wrapper

Negaflow.Engine                C++20 DLL
  Image IO / Color / Render / Export / Defects

Negaflow.RenderBridge          optional tiny native bridge
  SwapChainPanel attach/detach only when direct C# interop is insufficient
```

Shell 원칙:

- XAML tree와 view model은 UI thread ownership을 명확히 한다.
- long-running image, file, hash, scanner operation은 UI thread에서 실행하지 않는다.
- engine callback은 dispatcher를 거쳐 current request/revision 확인 뒤 view model에 적용한다.
- raw pixel buffer를 managed array로 round-trip하지 않는다.
- C# object reference를 engine에 영구 보관하지 않는다.
- window/panel handle은 attach/detach lifetime에만 사용한다.

## 7. 표면 매핑

| Negaflow surface | WinUI/native 구성 | 상세 명세 |
|---|---|---|
| Workspace | custom `Grid`, splitters, title/command chrome | [shell](shell-and-navigation.md) |
| Library | `ItemsView`, `TreeView`, custom selection/virtualization | [library](surfaces/library.md) |
| Develop | quiet grouped inspector + reusable slider/value control | [develop](surfaces/develop.md) |
| Canvas | `SwapChainPanel`, D3D/D2D pixels, XAML overlay | [canvas](surfaces/canvas.md) |
| Defects | canvas bridge + raw pointer input + XAML tool state | [defects](surfaces/defects.md) |
| Export | grouped inspector, queue/progress/transaction state | [export](surfaces/export.md) |
| Print | custom paper canvas + grouped layout/output inspector | [print](surfaces/print.md) |
| Scanning | capability-driven form + plugin process state | [scanning](surfaces/scanning.md) |
| Settings | left category navigation + scrollable grouped page | [settings](surfaces/settings.md) |
| Help/Legal | selectable localized document surface | parity inventory에서 추적 |

`NavigationView`를 모든 화면에 억지로 쓰지 않는다. Library/Develop/Print의 3-pane 작업 공간은 custom
`Grid`가 더 적합하고, Settings의 8개 category에는 left `NavigationView`가 적합하다.

## 8. collection control

`ItemsView`는 photo collection에 적합한 1차 후보다. 공식 문서상 UI/data virtualization, keyboard/mouse/
pen/touch input, accessibility를 지원하고 layout을 교체하면서 selection을 유지할 수 있다.

하지만 다음은 prototype으로 검증한다.

- 100, 1,000, 10,000, 100,000 item catalog
- thumbnail decode cancellation과 container recycle
- grid/compare/survey 전환 시 selection/anchor 보존
- variable aspect ratio와 `LinedFlowLayout`
- keyboard range selection과 accessibility item count
- fast scroll 중 GPU upload/backpressure
- item template allocation과 working set

측정 결과가 부족하면 `ItemsRepeater` 기반 custom virtualization을 고려한다. 처음부터 private virtualizing
panel을 만들지는 않는다.

## 9. pixel canvas와 XAML의 경계

```text
Direct3D/Direct2D
  photo pixels
  soft proof output
  histogram/tone curve raster when beneficial
  compare split and defect mask composite

WinUI XAML
  buttons, text, inspector controls
  crop handles and accessible hit targets
  status/HUD/readout
  menus, dialogs, focus visuals
```

원칙은 “픽셀은 engine, widget은 XAML”이다. 단, overlay geometry의 source of truth는 engine image coordinate
transform과 공유한다. XAML이 독립 zoom/pan math를 재구현하지 않는다.

`SwapChainPanel` 연결은 [canvas surface spec](surfaces/canvas.md)과
[SwapChainPanel canvas](swapchainpanel-canvas.md)를 따른다.

## 10. control styling

- system theme resource와 standard control template를 우선한다.
- Mica는 primary window backdrop 후보이지 모든 panel/card의 fill이 아니다.
- photo canvas와 inspector를 translucent layer로 덮지 않는다.
- ordinary field/action은 rest 상태에서 quiet하게 둔다.
- persistent selection만 track/thumb/selected fill을 유지한다.
- icon은 의미가 명확하거나 공간상 필요한 경우에만 사용한다.
- custom shadow, gradient, glass pill, decorative card wall을 금지한다.
- platform default animation도 대규모 image list에서 latency를 만들면 줄인다.
- motion reduction/high contrast 설정을 존중한다.

세부 form control은 [settings controls](settings-controls.md)를 따른다.

## 11. input

- pointer, wheel, precision touchpad, touch, pen을 서로 다른 source로 유지한다.
- canvas zoom/pan은 `PointerPoint`와 manipulation 상태를 image-space transaction으로 변환한다.
- brush/clone stamp는 raw pointer pressure/tilt support를 device evidence에 따라 사용한다.
- keyboard focus와 canvas tool capture를 혼동하지 않는다.
- menu access key와 workflow accelerator를 분리한다.
- custom shortcut recorder가 OS reserved chord를 거부한다.
- drag가 창 밖에서 취소되거나 pointer capture를 잃는 경로를 검증한다.

세부 계약은 [input and shortcuts](input-and-shortcuts.md)에 있다.

## 12. 접근성

WinUI XAML control의 기본 UI Automation 지원을 시작점으로 사용한다. custom canvas와 composite control은
별도 automation peer와 keyboard model이 필요하다.

- logical tab order
- native focus visual 보존
- accessible name/description/state/value
- list/grid selection pattern
- slider range/value/change semantics
- live progress는 과도한 announcement 없이 milestone만 전달
- color 이외의 clipping/gamut/error 표현
- high contrast에서 system brush 사용
- 200/400% text scaling
- Narrator + keyboard-only task completion

이미지를 볼 수 없는 사용자를 위한 metadata/selection/action surface는 canvas와 독립적으로 접근 가능해야 한다.

## 13. localization

- 기존 6개 언어 key/value를 `.resw`로 이관한다.
- source key와 localized string을 분리한다.
- technical identifier, format name, path는 번역하지 않는다.
- menu access key는 언어별 충돌 검토가 필요하다.
- 날짜, 숫자, unit, file size는 Windows globalization API를 사용한다.
- RTL layout과 BiDi path/chord isolate를 검증한다.
- hard-coded XAML text는 test에서 탐지한다.

“문자열 자산 그대로 이관”은 번역 내용을 보존한다는 뜻이다. Swift interpolation/pluralization/formatting을
기계적으로 `.resw`에 복사하면 동등성이 보장되는 것은 아니다.

## 14. window와 dialog

- main, Settings, auxiliary viewer의 ownership을 명시한다.
- 사용자·제품 채널별 primary UI process 하나를 기본으로 하고 second launch는 기존 process로 전달한다.
- modal operation은 `ContentDialog.XamlRoot` 또는 HWND-owner native dialog로 연결한다.
- dialog를 global static window에서 띄우지 않는다.
- picker와 color/profile dialog는 initiating window에 귀속한다.
- DPI/monitor 변경 후 bounds와 render target을 갱신한다.
- app activation이 기존 instance로 전달될 때 현재 destructive transaction을 침범하지 않는다.
- main close의 비동기 catalog 승인과 5초 안에 응답해야 하는 session-end 처리를 같은 callback으로
  축약하지 않는다.

instance election, activation queue, normal close, `WM_QUERYENDSESSION`, crash/restart의 전체 계약은
[애플리케이션 수명주기](application-lifecycle.md)가 소유한다.

## 15. 성능 budget

UI performance는 engine throughput과 별도로 측정한다.

- main window first usable frame
- Library scroll frame pacing과 input latency
- Develop slider pointer-to-present latency
- pane resize와 inspector scroll hitch
- Settings open/category switch
- XAML object/container count와 managed allocation
- UI thread long task와 dispatcher queue depth
- x64/ARM64 working set

목표 숫자는 representative hardware 측정 전에 임의 확정하지 않는다. 측정 fixture와 percentile을
[backend 선택](../12-performance/backend-selection.md)과
[성능 실패 모드](../12-performance/known-failure-modes.md)에서 정의한다.

## 16. 검증 matrix

- 승인된 API 하한 image와 Stable 시점의 지원 Windows 11 release
- x64 Intel, x64 AMD, ARM64 Qualcomm
- Intel/NVIDIA/AMD/Qualcomm GPU와 WARP fallback
- 100/150/200% display scaling, monitor 간 이동
- SDR/HDR monitor 조합
- light/dark/high contrast
- 6개 언어 + RTL smoke
- mouse/precision touchpad/touch/pen/keyboard
- local/OneDrive-redirected/network/removable storage
- packaged spike와 실제 unpackaged installer build

자동화만 통과하고 실제 app을 열지 않았다면 visual QA 완료라고 부르지 않는다.

## 17. 남은 위험

- XAML Designer 부재에 따른 visual iteration 비용
- `ItemsView`가 Negaflow의 대규모 heterogeneous photo grid에서 충분한지 미측정
- C# ↔ native panel interop lifetime
- WinUI patch별 rendering/input regression
- unpackaged deployment에서 picker, activation, file association 차이
- custom inspector control의 keyboard/UI Automation 품질
- ARM64 native dependency와 scanner plugin availability

## 18. 공식 자료

- [Windows App SDK overview](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/)
- [Windows App SDK release channels](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/release-channels)
- [Get started with WinUI](https://learn.microsoft.com/en-us/windows/apps/get-started/winui-get-started-overview)
- [Windows App SDK platform overview](https://learn.microsoft.com/en-us/windows/apps/develop/platform/)
- [What is supported when migrating to WinUI 3](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/what-is-supported)
- [ItemsView](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/itemsview)
- [Accessibility overview](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessibility-overview)
- [Keyboard interactions](https://learn.microsoft.com/en-us/windows/apps/develop/input/keyboard-interactions)
