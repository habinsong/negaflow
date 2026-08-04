# WinUI 셸 기반

기준일: 2026-08-04
상태: 셸·배치·지역화·표시 설정 기반 구현, 제품 기능은 미완료

## 목적

현재 SwiftUI 제품을 새로 디자인하지 않고 Windows 네이티브 창 규칙에 맞춰 화면 계층과 치수를 옮깁니다.
이번 기반은 Library, Develop, Print, Settings의 실제 데이터 기능을 완성한 것이 아니라 이후 기능을 같은
배치와 상태 계약 안에 연결할 수 있는 실행 가능한 셸입니다.

권위 수치는 `baseline/swift-ui-metrics.json`, 표시 문자열은 현재 Swift localization table입니다. 외부 UI
template, icon pack, theme 또는 다른 사진 프로그램의 화면 코드는 사용하지 않았습니다.

## 프로젝트 경계

```text
src/Shell.Core/
  ShellPreferences.cs             WinUI에 의존하지 않는 표시 상태와 기본값
  ShellLayoutMetrics.cs           Swift 기준 치수
  WorkspaceLayoutCalculator.cs    현재 작업영역 폭에 따른 panel clamp

src/Shell/
  MainWindow.*                    최대화 시작, Windows caption inset, Settings 수명
  SettingsWindow.*                760×640 설정 창과 theme 적용
  Localization/AppResources.cs    PRI resource 조회와 형식화
  Services/                       원자적 설정 저장, native 상태, DPI 크기 환산
  Views/                          toolbar, 작업공간, filmstrip, status, settings

tests/Shell.UnitTests/
  Program.cs                      기본값·정규화·적응형 폭·Swift 수치 동기화
```

표시 상태, 창 I/O, native ABI 확인과 개별 화면을 서로 분리했습니다. `WorkspaceShellView`는 화면 조립과
전환만 담당하고, 파일 가져오기·현상·출력·scanner 업무 로직을 소유하지 않습니다.

## Windows App SDK와 배포 경계

셸은 집계 package 대신 필요한 component만 직접 고정합니다.

- `Microsoft.WindowsAppSDK.Runtime 1.8.260710003`
- `Microsoft.WindowsAppSDK.WinUI 1.8.260709004`
- `Microsoft.Windows.SDK.BuildTools 10.0.26100.7705`는 build-only

`Microsoft.WindowsAppSDK 2.3.1` 집계 graph는 사용하지 않습니다. 조사 당시 그 graph의 WinUI component
license가 Engineering Preview 조건이었고, 현재 셸에 필요 없는 AI/ML/Widgets package까지 가져왔기
때문입니다. 1.8 WinUI component license는 WindowsAppSDK NuGet이 app에 배치한 파일의 재배포를 허용하지만,
이는 제품 전체의 법률 검토를 대신하지 않습니다.

현재 셸은 unpackaged, framework-dependent입니다. 따라서 실행 대상에는 .NET 10 runtime과 Windows App
Runtime 1.8이 필요하며, 설치 관리자가 이를 연결하거나 명확히 선행 조건으로 안내해야 합니다. 새로 만든
x64 Debug 출력은 하위 파일을 포함해 50개, 40,633,234 byte였고 AI/ML/Widgets/ONNX/DirectML 이름과
경로는 0개였습니다. WebView2는 WinUI의 transitive package이며 현재 화면은 web content를 사용하지
않지만, build output의 loader/projection에 대한 BSD-3-Clause notice는 배포 시 포함해야 합니다.

공식 근거:

- [Windows App SDK 1.8 component packages](https://github.com/microsoft/WindowsAppSDK/discussions/5810)
- [Framework-dependent unpackaged deployment](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps)
- [Unpackaged WinUI app distribution](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/unpackage-winui-app)
- [WinUI 1.8 license](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.WinUI/1.8.260709004/License)
- [WinUI 2.3.2 Engineering Preview license](https://www.nuget.org/packages/Microsoft.WindowsAppSDK.WinUI/2.3.2/License)

## Main window와 Windows caption

- main window는 특정 `1600×900` 크기로 만들지 않고 현재 모니터의 전체 작업영역으로 최대화합니다.
- 900×640은 초기 크기가 아니라 사용자가 창을 줄일 때의 최소 content 크기입니다.
- toolbar는 client area를 title bar로 확장하되 최소화·최대화·닫기 버튼은 Windows가 그립니다.
- LTR Windows caption button은 오른쪽에 있으므로 `AppWindow.TitleBar.RightInset`을 런타임마다 읽습니다.
- `LeftInset`과 `RightInset`은 physical pixel이므로 `XamlRoot.RasterizationScale`로 나눠 logical column에
  반영합니다. 창 크기나 DPI가 달라지면 다시 계산합니다.
- RTL이나 다른 caption 배치도 같은 left/right runtime inset을 사용하므로 고정 여백으로 추측하지 않습니다.

관련 Microsoft 근거:

- [Title bar customization](https://learn.microsoft.com/en-us/windows/apps/develop/title-bar?tabs=winui3)
- [WinUI 3 desktop app structure](https://learn.microsoft.com/en-us/windows/apps/develop/ui/windows-app-sdk-app-structure)

## 화면 계층

### Toolbar

- 높이 40, 우측 작업공간 cluster 502, 작업공간 링크 266을 Swift source와 맞춥니다.
- Library → Develop → Print 순서와 선택 상태를 유지합니다.
- 왼쪽 quick export/export는 아직 기능이 없으므로 disabled 상태입니다.
- sidebar, filmstrip, inspector 표시 상태는 즉시 반영하고 저장합니다.
- caption button 영역에는 상호작용 가능한 control을 배치하지 않습니다.

### Library

- 기본 controls panel 430, tab rail 76, browser header 44입니다.
- 1340 이상에서는 controls panel을 300…560, 그 미만에서는 240부터 현재 폭에 맞춰 clamp합니다.
- 현재는 빈 library 상태만 표현하며 가져오기 button은 disabled입니다.
- 창작 설명을 넣지 않고 기존 `importHint`, `noImages`, `library*` 문자열만 사용합니다.

### Develop와 Print

- 좌 panel, 중앙 canvas, 우 inspector가 overlay가 아니라 실제 column 폭을 나눕니다.
- 좌·우 기본 폭은 각각 430이고 현재 창 폭에서 중앙 최소 폭을 보존합니다.
- filmstrip 기본 높이는 192, 허용 범위는 112…340이며 drag 종료 시 한 번만 저장합니다.
- filmstrip 높이 keyboard step은 16이고 접근성 값은 Swift의 기존 형식 문자열을 사용합니다.
- Print의 빈 중앙은 Swift `ContentUnavailableView(noFrame)`와 같은 의미만 표시합니다. 임시 종이 preview나
  다음 단계 설명을 만들지 않습니다.

### Settings

- 고정 제품 계약인 760×640 창과 8개 category 순서를 유지합니다.
- General의 appearance만 현재 동작하며 system/dark/light가 main과 settings에 함께 저장·적용됩니다.
- 일반 이미지 SHA-256은 사용자 요구에 따라 Disk에 추가한 알려진 Windows 차이입니다.
- `ShellPreferences.ImageContentHash` 기본값과 비정상 enum 정규화 fallback은 모두 `Off`입니다.
- 미구현 control은 실제 동작처럼 보이지 않도록 disabled이며 설명을 창작하지 않습니다.
- Scan page는 특정 backend를 표시하지 않습니다. SANE 경계는
  [`ADR-0006`](../decisions/0006-scanner-plugin-boundary.md)을 따릅니다.

## 문자열 원본과 6개 언어

다음 Swift 원본만 Windows 표시 문자열로 가져옵니다.

- `AppLocalizedText+{Language}.swift`
- `AppLocalizedPhrase+{Language}.swift`
- `AppLocalization+Accessibility.swift`
- 언어 선택기 이름은 `AppLanguage.displayName`의 기존 literal

`baseline/swift-ui-string-map.json`은 실제 Windows 셸에서 사용하는 key/property를 명시합니다.
`scripts/sync-swift-ui-strings.ps1`은 원본을 읽어 다음 PRI 입력을 생성합니다.

- `en-US`
- `ko-KR`
- `ja-JP`
- `zh-Hans`
- `fr-FR`
- `de-DE`

생성 리소스는 손으로 번역하지 않습니다. `-Check`는 Swift 원본이나 mapping과 다른 생성물을 실패시킵니다.
XAML은 단일 property resource에 `x:Uid`를 쓰고, 같은 원문 key가 여러 control property에 쓰이는 경우
`ResourceLoader`로 정확한 property identifier를 읽습니다. Microsoft 문서에 따라 code lookup에서는
점 대신 `/`를 사용합니다.

- [Localize strings in a WinUI 3 app](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/localize-winui3-app)

화면에 직접 남은 literal은 `negaflow`, `SHA-256`, `JPEG`, `PNG`, `A4`, `ISO`, 숫자·단위·빈 값과
`AppLanguage.displayName` 원문뿐입니다.

## 접근성

- 작업공간, panel toggle, settings category, image hash에 고정 Automation ID를 둡니다.
- 선택/미선택과 켬/끔 help text는 Swift 접근성 table의 기존 문자열을 사용합니다.
- filmstrip resize control은 이름과 현재 높이를 노출하고 keyboard Up/Down을 지원합니다.
- Swift에서 `accessibilityHidden(true)`인 좌·우 panel resize handle은 Windows control view에서도
  제외하고 raw view에만 둡니다.
- 상태 bar는 색상뿐 아니라 `idleStatus` 또는 `capabilityUnavailable` 텍스트와 ABI detail을 함께 표시합니다.

## 설정 저장

`PresentationSettingsStore`는 JSON을 임시 파일에 쓴 뒤 같은 volume에서 교체합니다. 잘못된 JSON,
I/O 실패, 권한 실패는 안전한 기본값으로 돌아갑니다. 표시 상태만 저장하며 원본 이미지, catalog, scanner
파일을 읽거나 이동하지 않습니다.

## 현재 검증된 범위

- x64 Debug/Release managed locked restore/build: 경고 0, 오류 0
- ARM64 Debug/Release managed locked restore/cross-build: 경고 0, 오류 0
- Swift 문자열 generator check: 6개 언어 최신
- UTF-8 XAML/RESW/project XML parse: 100개
- Shell unit test: 45 assertion
- 실제 maximized main window: `computer-use` logical capture 2560×1392
- Windows caption button 오른쪽 배치와 toolbar non-overlap
- Library, Develop, Print 화면 전환과 한국어 PRI 표시
- 접근성 tree의 workspace 선택, panel 상태, filmstrip 높이와 native ABI 상태
- Settings 실제 창 열기와 Disk category 이동
- `settings.disk.image-sha256` 접근성 상태 `끔`; toggle을 켜지 않고 검증
- direct/transitive NuGet 취약점 0개 보고

Settings 창은 760×640 계약에 대해 실제 capture가 748×634로 관찰됐으므로, DPI/non-client 영역을 포함한
정확한 pixel 크기 판정은 아직 남아 있습니다. 현재 화면 셸은 실제 사진 가져오기, catalog, GPU canvas,
Develop graph, export, print engine 또는 scanner host 완료를 의미하지 않습니다.

## 남은 작업

1. Settings 8개 category 전체 keyboard 이동, appearance 재시작 persistence와 정확한 window size 검증
2. 900×640과 여러 DPI·High Contrast·Reduce Motion/Transparency matrix 검증
3. 실제 catalog/import 상태를 Library에 연결
4. native handle/event/cancellation C ABI와 GPU canvas 연결
5. 기능이 연결될 때 Swift의 전체 control·empty/loading/error 상태를 단계별 이식
