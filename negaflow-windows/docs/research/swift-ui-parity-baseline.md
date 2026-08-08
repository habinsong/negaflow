# Swift UI 패리티 기준선

기준일: 2026-08-04
상태: 소스·저장소 캡처 기준선 고정, Windows 전체 작업영역 셸 비교 진행 중
macOS 기준 revision: `2fa1d6297378673b58b8bec72025e968ccc3125c`

## 목적

Windows UI를 새로 디자인하지 않고 현재 SwiftUI 제품의 화면 계층, 배치, 크기, 상태 전이와 접근성 의미를
옮긴다. 수치는 [`baseline/swift-ui-metrics.json`](../../baseline/swift-ui-metrics.json)에 기계 판독 가능한
형태로도 고정한다. Windows 구현과 test는 이 파일을 같은 source of truth로 사용한다.

`99% 동일`은 현재 달성 사실이 아니라 최종 검증 목표다. 소스 수치가 같아도 macOS와 Windows의 글꼴 raster,
native control, scrollbar, window caption이 다르므로 실제 100% 배율 screenshot과 keyboard/UI Automation
검증 전에는 패리티 통과로 기록하지 않는다.

Windows main window의 검증 기준은 고정 `1600×900`이 아니라 실행 모니터의 최대화된 전체 작업영역이다.
`1600×900` macOS capture는 내부 anchor와 비율을 비교하는 보조 자료이며 Windows 시작 크기 계약이 아니다.

## 증거

### Swift 소스

| 영역 | 권위 소스 | 고정한 내용 |
|---|---|---|
| 창과 scene | `Sources/negaflowApp/App/AppEntry.swift` | main 최소 900×640, hidden title bar, Settings 760×640, Help 680×560 |
| 최상위 셸 | `Sources/negaflowApp/App/Content/ContentView.swift` | 40pt toolbar, divider, workspace, 30pt status, module 순서와 전이 |
| Develop/Print 분할 | `ContentView+Workspace.swift`, `ContentView+PrintWorkspace.swift` | 좌·중앙·우 독립 column, 중앙 하단 filmstrip/status |
| 적응형 폭 | `Features/Workspace/WorkspaceAdaptiveLayout.swift` | 1340 threshold, 430 기본 panel, min/max와 중앙 최소폭 |
| panel resize | `Features/Workspace/WorkspaceResizablePanel.swift` | 8pt handle, global delta, drag 중 비애니메이션, 종료 시 저장 |
| toolbar | `Features/Workspace/Toolbar/WorkspaceToolbar*.swift` | 40pt 높이, 502pt 우측 cluster, 266pt workspace links, 26×24 버튼 |
| Develop 좌·우 panel | `WorkflowSidebar.swift`, `WorkspaceInspectorPane.swift` | 76/48pt rail, 300pt compact threshold, header/content padding |
| 중앙과 상태 | `ContentView+CenterStatus.swift` | canvas/filmstrip/status 계층, 30pt status와 진행 slot |
| filmstrip | `WorkspaceFilmstrip.swift`, `FilmstripSizing.swift`, `FrameStepButton.swift` | 192pt 기본, 112…340pt, 최대 3행, card와 resize 수치 |
| Library | `LibraryWorkspaceView*.swift`, `LibraryBrowserHeader.swift`, `SidebarViews.swift` | 430pt controls, 44pt header, 18pt grid padding, card scale와 하단 controls |
| Settings | `Settings/AppSettingsView.swift`, `AppSettingsTab.swift`, `AppSettingsComponents.swift` | 760×640, 8개 category 순서, grouped form 의미 |
| theme | `Settings/AppPresentationSettings.swift`, `Shared/UI/AdaptiveSurface.swift` | system/dark/light, canvas black/gray/white, 투명도 감소 시 opaque surface |

### 저장소 reference capture

다음 6장은 모두 1600×900이며, 한국어 라이트/다크에서 Library/Develop/Print의 전체 구도를 보여 주는
보조 reference다.

- `docs/images/ko/library-light.webp`, `library-dark.webp`
- `docs/images/ko/develop-light.webp`, `develop-dark.webp`
- `docs/images/ko/print-light.webp`, `print-dark.webp`

이 이미지는 시각 비교 입력일 뿐 Windows app payload에 복사하지 않는다. 사진 pixel과 사용자 TIFF도 UI
fixture로 저장소에 편입하지 않는다.

## 화면 계약

### Main window

```text
40  toolbar / integrated title area
 1  system divider
 *  active workspace
```

- 최소 content 크기는 900×640이다.
- 초기 main window는 현재 모니터의 전체 작업영역으로 최대화한다.
- 작업공간 순서는 `Library(0) → Develop(1) → Print(2)`다.
- 모듈 전환은 0.14초이며 Reduce Motion에서는 motion을 제거한다.
- main accessibility root는 `negaflow.main`이다.
- file drop highlight는 12pt radius, 3pt accent stroke, 6pt inset이다.

### Toolbar

- 전체 높이 40, 세로 padding 6, 주 HStack spacing 10이다.
- 우측 cluster는 502pt이고 그 안의 workspace links는 266pt다.
- Library/Develop/Print 버튼은 min 74, max 86, min height 24, 14.5pt semibold/bold다.
- panel/appearance/utility icon button은 26×24이고 icon은 13~14pt다.
- 왼쪽에는 scan/export, 가운데에는 활성 사진 context, 오른쪽에는 workspace/panel/theme/menu가 온다.
- 실제 기능이 없는 scan/export는 enabled처럼 꾸미지 않는다.
- Windows LTR caption button은 오른쪽에 두고 실제 `RightInset`을 DPI 환산해 toolbar가 침범하지 않게 한다.

### Library

```text
[430 default controls: 76 rail | tab content] | [browser: 44 header | collection]
                                                   [bottom view picker + search]
```

- controls는 430pt 기본이며 1340pt 이상에서 300…560pt, compact에서 240pt 이상이다.
- browser header는 44pt, horizontal 16, vertical 8이다.
- grid padding은 18, folder section spacing은 22다.
- 기본 card width는 `190 × scale`; scale은 0.72…1.42, step 0.08이다.
- view picker/search width는 280, search height는 28, 하단 inset은 14다.

### Develop

```text
[left 430] | [canvas                 ] | [right 430]
           | [filmstrip 192, 112…340]
           | [status 30              ]
```

- 좌·우 panel은 overlay가 아니며 중앙과 폭을 나눈다.
- regular panel은 300…560pt, compact panel은 220pt 이상이다.
- 양쪽 panel이 열린 상태에서도 중앙은 regular 480pt, compact 400pt를 보존한다.
- sidebar rail은 regular 76, 300pt 미만 panel에서 48이다.
- inspector body는 leading 8, trailing 20(regular)/8(compact), vertical 14다.
- canvas background 값은 black 0.07, gray 0.5, white 0.97 luminance다.

### Filmstrip와 status

- filmstrip 기본 높이는 192, 범위는 112…340이다.
- top resize 영역은 7pt를 예약하고 실제 bar는 6pt, grip은 44×2다.
- 내부 padding은 horizontal 12/vertical 10, grid spacing은 10이다.
- card scale은 0.56…1.34, nominal height 152, 최대 자동 높이 156, 최대 3행이다.
- drag 동안 저장소에 쓰지 않고 종료 시 한 번 저장한다. keyboard는 16pt 단위로 조절한다.
- status bar는 30pt이고 완료/오류/engine state를 색상만으로 표현하지 않는다.

### Settings

- 창 크기는 760×640이다.
- category 순서는 General, Interface, Workflow, Scan, Disk, Export, Shortcuts, Legal이다.
- 최신 사용자 요구가 기존 Windows 문서의 left navigation 제안보다 우선하므로, category의 위치와 크기는
  Swift `TabView`의 상단 배열을 먼저 재현한다.
- 일반 이미지 SHA-256은 macOS 기준선에 없지만 명시적 제품 요구이므로 Disk category에 알려진 차이로
  추가한다. 기본값은 반드시 `off`이며 사용자가 직접 켜기 전 파일을 읽지 않는다.

## Windows에서 허용하는 차이

다음만 비교 mask 또는 의미 동등성으로 처리한다.

1. Windows caption buttons와 macOS traffic lights. 운영체제 control을 위조하지 않는다.
2. Segoe UI/Segoe Fluent Icons와 SF Pro/SF Symbols의 glyph raster 차이.
3. native scrollbar, focus visual, tooltip, context menu와 picker chrome.
4. Reduce Transparency/High Contrast에서 system opaque brush로 바뀌는 surface.
5. 사용자 요구로 추가된 이미지 SHA-256 기본-off 설정과 native engine bootstrap 상태.

그 밖의 panel 순서, 기본 폭, header/toolbar/filmstrip/status 높이, padding, 선택 상태와 숨김 동작은 임의로
바꾸지 않는다.

## 검증 절차

1. 각 검증 모니터의 최대화된 전체 작업영역에서 Windows screenshot을 먼저 기록한다.
2. 1600×900 reference는 caption/font/scrollbar mask를 적용한 내부 anchor 비율 비교에만 사용한다.
3. 900×640, 1339×900, 1340×900, 1600×900과 전체 작업영역 폭에서 panel clamp와 중앙 최소폭을 검사한다.
4. light/dark/high contrast, Reduce Motion, Reduce Transparency, 100/150/200% scaling을 검사한다.
5. keyboard로 workspace, panel toggle, filmstrip resize, Settings category와 SHA toggle을 조작한다.
6. UI Automation name/state/value와 고정 identifier를 snapshot으로 비교한다.

2026-08-04 실제 x64 Debug 실행에서 main window가 2560×1392 logical 전체 작업영역으로 열렸고, 오른쪽
Windows caption button과 toolbar가 겹치지 않음을 확인했다. Library, Develop, Print의 기본 empty state와
한국어 PRI도 실행 확인했다. Settings를 실제로 열어 Disk category의 이미지 SHA-256 접근성 상태가 `끔`임을
확인했고 toggle은 켜지 않았다. Settings capture는 748×634로 관찰돼 760×640 계약의 DPI/non-client
pixel 판정은 남아 있다. 이 증거는 첫 셸 배치 검증이며 전체 Settings keyboard matrix, DPI matrix와
pixel-level 99% 판정은 아직 **미검증**이다.

## 권리·의존성 판단

- 화면 구조와 capture는 같은 Negaflow 저장소의 고정 revision에서 왔으며 외부 제품 디자인을 복제하지 않는다.
- Microsoft sample UI 코드는 복사하지 않고 공식 template의 project contract만 조사했다.
- Windows UI는 `Microsoft.WindowsAppSDK.Runtime 1.8.260710003`과
  `Microsoft.WindowsAppSDK.WinUI 1.8.260709004` component를 직접 고정한다. 1.8 WinUI license는 NuGet이
  app에 배치한 파일의 재배포를 허용하며, package license/notice를 보존해야 한다.
- `Microsoft.WindowsAppSDK 2.3.1` 집계 graph는 쓰지 않는다. 그 graph의 WinUI component license가
  Engineering Preview 조건이고 현재 셸에 필요 없는 AI/ML/Widgets package까지 포함했기 때문이다.
- WinUI가 transitive로 가져오는 `Microsoft.Web.WebView2 1.0.3179.45`의 loader/projection은 현재 출력에
  존재하므로 binary 배포 때 해당 BSD-3-Clause license를 재현해야 한다. 현재 셸은 web content를 사용하지 않는다.
- Windows SDK BuildTools는 build-only이며 제품 runtime component로 기록하지 않는다.
- CommunityToolkit, icon pack, 외부 theme/template는 사용하지 않는다.

공식 근거:

- [Windows App SDK 1.8 component packages](https://github.com/microsoft/WindowsAppSDK/discussions/5810)
- [Framework-dependent unpackaged deployment](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps)
- [WinUI 1.8 license](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.WinUI/1.8.260709004/License)
- [WinUI 2.3.2 Engineering Preview license](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.WinUI/2.3.2/License)
- [WebView2 1.0.3179.45 license](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.3179.45/License)
- [WinUI quick start](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/set-up-your-development-environment)
- [Title bar customization](https://learn.microsoft.com/en-us/windows/apps/develop/title-bar?tabs=winui3)
- [WinUI localization](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/localize-winui3-app)
